# Architectural decisions

## Decision: Three Vault nodes with Raft

Three voters require quorum two, so the cluster can tolerate one node failure. Raft avoids adding Consul, but losing two voters removes quorum. Replacement and recovery must preserve Raft state; a replacement joins the existing cluster and must never initialize independently.

## Decision: Use laptop SSH over SSM for private-node administration.

Use laptop SSH tunneled through `AWS-StartSSHSession`: this keeps nodes private without inbound port 22 or an always-on management host. Ansible uses ordinary SSH with a dedicated laptop key and pinned host keys. IAM for SSM, SSH authentication, host verification, and Linux privilege escalation are separate controls. The controller needs SSM Run Command/session permissions; the node's `AmazonSSMManagedInstanceCore` role does not grant them. Session Manager does not record SSH command contents.

## Decision: AWS KMS auto-unseal

KMS handles Vault seal/unseal operations; Raft remains live storage and S3 is reserved for snapshots. This avoids manual unseal after restarts but makes preservation of the original KMS key and tight instance-role permissions essential.

## Decision: Store bootstrap recovery material in a separate Secrets Manager secret.

Vault initialization returns recovery shares and an initial root token once. A separate recovery KMS key encrypts one Secrets Manager bundle; Terraform manages only resource metadata, while the one-time Ansible bootstrap stores the value through a controller helper.

### Alternatives Considered

- Reuse the auto-unseal key: rejected because it combines distinct security purposes and permission lifecycles.
- Put values in Terraform variables/resources: rejected because secret values would enter state or plans.
- Create separate secrets for each share and token immediately: deferred to avoid needless complexity for this single-operator lab; a combined bundle means break-glass read access exposes both.

### Consequences

The bootstrap role has scoped write/metadata access; a separate break-glass identity handles retrieval, and Vault nodes get no recovery-secret access. The same-account bundle is not an independent custody boundary and costs money. Lost init output cannot be recovered by rerunning initialization; only one authorized operator should bootstrap at a time.

## Decision: Public NLB, private Vault nodes, TLS pass-through

The internet-facing NLB spans three public AZ subnets and forwards TCP 443 to Vault on TCP 8200. Vault nodes remain private; Vault terminates TLS for `vault.ahmedferjani.com`. This keeps the NLB outside the API decryption boundary and avoids a second TLS hop. The trade-off is that certificate distribution/renewal and TLS validation on every node remain operational responsibilities. The operator reports the single-node endpoint works; HA routing still needs validation (see [raft-ha.md](raft-ha.md)).

## NLB target health and cross-zone policy: HA validation pending

Cross-zone behavior, standby forwarding/redirects, leader transitions, and health convergence are still untested on a three-node cluster. The health-check and fail-open trade-offs are described in [raft-ha.md](raft-ha.md); validate them before claiming HA.

## Decision: Use AWS discovery for Raft peer joining; keep one public DNS endpoint.

Use one Route 53/NLB client endpoint; keep per-node `cluster_addr` private. Raft `retry_join` uses AWS discovery filtered by the cluster tag, avoiding static per-instance DNS records.

### Consequences

- Vault's instance role has `ec2:DescribeInstances` scoped by the `ec2:Region` condition; the discovery query filters results by the dedicated cluster tag. AWS requires `Resource="*"` for this action because it does not support resource-level scoping.
- The ASG launch template tags instances for discovery; confirm the tag filter remains cluster-specific.
- DNS identity does not preserve Raft identity; replacement nodes must join the existing cluster, not initialize a new one.
- Validate TLS peer verification when auto-join discovers private IPs, including certificate SAN and `leader_tls_servername` behavior, before starting nodes.

## Decision: Provide private Vault nodes with same-AZ NAT; defer interface endpoints.

Vault nodes require outbound access to the HashiCorp RPM and OS repositories, KMS for auto-unseal, and EC2 APIs for Raft peer discovery. Keep nodes in private subnets without public IPs. Use one NAT Gateway per AZ for HTTPS egress. KMS/EC2 interface endpoints are a possible later improvement, but are deferred for this cost-sensitive lab; current AWS API traffic uses NAT.

### Alternatives Considered

- No egress, with packages pre-baked into reviewed AMIs and no runtime AWS API endpoints.
- One shared NAT Gateway for lower cost, accepting cross-AZ dependency and transfer charges.
- A controlled internal RPM mirror or egress proxy instead of unrestricted public HTTPS through NAT.

### Why

- Supports package installation and updates while keeping Vault instances private.
- Interface endpoints could keep KMS and EC2 API traffic on AWS private connectivity if added later.
- Same-AZ NAT routing avoids depending on another AZ for general egress.

### Consequences

- Three NAT Gateways/EIPs incur recurring charges; adding interface endpoints would add more.
- Security-group HTTPS egress through NAT is not destination-domain filtering. Use an internal mirror or egress control if public HTTPS needs tighter restriction.
- Same-AZ NAT routes and HTTPS egress are implemented; AWS API traffic uses NAT until interface endpoints are justified.
