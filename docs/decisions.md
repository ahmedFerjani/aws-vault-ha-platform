# Architectural decisions

## Decision: Use a 3-node Vault cluster with Raft integrated storage.

A three-node cluster provides a quorum of 2, so one EC2 node can fail without losing cluster availability. This keeps the design simple and avoids introducing extra coordination systems like Consul. The cluster still needs careful handling during recovery and replacement because Vault is a stateful service, not a stateless application.

### Benefits

- High availability with a simple three-node model
- One-node failure is tolerated without losing quorum
- Clear operational model for leader election and recovery

### Trade-offs

- Recovery and node replacement must follow strict Raft rules
- Losing two nodes can still break quorum and impact availability
- The system requires more operational discipline than a stateless app

## Decision: Use SSH over SSM for the current laptop-driven access iteration.

### Context

Direct management-to-node SSH passed its one-node tests, but required a control host and inbound TCP 22. The operator now chooses laptop-driven SSH tunneled through Session Manager. This supersedes the requirement for a management EC2 host. After successful laptop access and operator-reported Ansible deployment, the unused module, commented call, and management-only inputs were removed. A resource-address check found no management resources in current Terraform state; cleanup does not execute an AWS apply.

### Decision

Remove the management module call and Vault management SSH ingress from the active root configuration. Use ordinary SSH via `AWS-StartSSHSession`, with instance IDs, verified host keys, and a dedicated laptop key. Keep Vault nodes private and their existing SSM instance role and outbound HTTPS connectivity. Playbook tasks need not change; inventory/SSH configuration must change after fresh instance discovery. Do not initialize Vault as part of access testing.

### Alternatives Considered

Direct private-IP SSH from a management EC2 host; a native Ansible SSM connection plugin; a future dedicated CI runner.

### Why

SSM removes inbound SSH rules and the always-on management-host cost while allowing IAM-controlled tunnel initiation. A controller outside the VPC does not need direct private-IP routing for this transport.

### Consequences

The controller needs AWS CLI, Session Manager plugin, and narrowly scoped session permissions. `AmazonSSMManagedInstanceCore` on a target is not controller permission to start sessions. SSH authentication, host-key verification, and sudo remain separate controls. CloudTrail can record session API activity, but Session Manager cannot capture SSH command contents. Public-key provisioning for replacement nodes remains unresolved; the manual trusted-SSM step is only for this test. Validate SSM Online status, strict SSH, Ansible ping, and become on one node before declaring the transport complete. Review any plan destruction of existing management resources explicitly; no apply is performed by this change. Future CI controller placement will be designed separately.

## Historical decision: Use an AWS control host as the Ansible and runner control plane (superseded for current access iteration).

The earlier approach placed Ansible on a small EC2 control host with private-network access to Vault. Its direct SSH path was tested, but the host was not necessary once laptop SSH-over-SSM was validated. This section records former trade-offs, not current deployment instructions. Future CI controller placement remains undecided.

### Benefits

- Keeps the Vault cluster private and reduces the attack surface
- Provides a central control point for Ansible orchestration; command auditing requires additional controls
- Allows a GitHub self-hosted runner to access private Vault nodes over the VPC without exposing them publicly
- Makes AWS-native operations and SSM break-glass access simpler
- Supports private-network automation without requiring laptop VPC connectivity

### Trade-offs

- Adds one small EC2 budget item for the control host
- Requires a clearly scoped security group and SSH access policy
- Requires disciplined key handling, runner registration, and least-privilege IAM design
- A runner is still an EC2 instance and must be treated as a controlled operational component rather than a stateless abstraction

## Decision: Use AWS KMS for auto-unseal.

AWS KMS removes the need for manual unseal during EC2 restarts or replacement and keeps the cluster recoverable in a native AWS environment. It also requires tightly scoped IAM permissions and a clear separation between KMS, Raft, and S3 responsibilities.

### Benefits

- Reduces operational friction during recovery and restarts
- Fits naturally with AWS-managed infrastructure
- Improves resilience for EC2-based Vault nodes

### Trade-offs

- KMS permissions must be tightly restricted
- KMS is not Vault storage and must not be confused with Raft
- S3 remains a backup destination, not a live storage backend

## Decision: Use an internet-facing NLB with private Vault nodes.

Clients reach the Vault API through a TLS-enabled public NLB. The NLB is placed in public subnets across three Availability Zones; Vault EC2 instances remain in private subnets without public IPs or direct internet routes.

### Benefits

- Provides a stable public entry point across Availability Zones
- Keeps Vault nodes off the public internet
- Separates inbound client access from private-node outbound egress

### Trade-offs

- The public endpoint requires strict TLS, listener, and target security-group controls
- Public subnets and an Internet Gateway are required for the NLB
- NAT Gateways are not part of inbound access and must be justified separately for private-node egress

## Decision: Use NLB TCP pass-through for Vault client TLS.

The NLB will forward TCP port 443 to the Vault API target port without terminating TLS. Vault presents the certificate for `vault.ahmedferjani.com`; clients establish and validate TLS directly with Vault. The NLB remains a Layer 4 forwarding component and does not decrypt Vault requests.

### Alternatives Considered

- Terminate client TLS at the NLB with an ACM certificate, then establish a separate TLS connection to Vault.

### Why

- Keeps the NLB outside the Vault API decryption trust boundary.
- Provides a single client-to-Vault TLS session and preserves Vault's own TLS endpoint.
- The domain is managed in Route 53, allowing DNS-01 certificate validation without exposing Vault nodes for ACME challenges.

### Consequences

- Vault nodes must securely receive and renew their TLS certificate and private key.
- The client certificate must cover `vault.ahmedferjani.com`; peer TLS verification for AWS-discovered private IPs must be tested with the configured SNI/server name and CA.
- Certificate renewal and deployment become an operational responsibility; private keys must never be committed.
- Compared with NLB TLS termination, the NLB does not need an ACM listener certificate and does not see plaintext requests.

## Decision: Use AWS discovery for Raft peer joining; keep one public DNS endpoint.

Use `vault.ahmedferjani.com` as the public client endpoint, pointing to the NLB through a Route 53 alias. Do not assign permanent numbered private DNS names to ASG instances. Configure Vault Raft `retry_join` with AWS discovery, selecting eligible instances by a dedicated cluster tag and resolving their current private IPv4 addresses. Each node advertises its current private address as `cluster_addr`; `api_addr` advertises the public NLB hostname for client redirects.

### Why

- Clients use one stable endpoint while Vault nodes remain privately addressed.
- Vault can advertise one stable public endpoint for clients while using current private addresses for Raft traffic.
- AWS discovery avoids custom Route 53 record allocation and stale private records when ASG instances are replaced.

### Consequences

- Vault's instance role needs narrowly scoped `ec2:DescribeInstances` access for discovery; inspect supported IAM scoping before implementation.
- The ASG launch template must tag instances with a dedicated cluster-discovery tag, and discovery must filter to this cluster only.
- DNS identity does not preserve Raft identity; replacement nodes must join the existing cluster, not initialize a new one.
- Validate TLS peer verification when auto-join discovers private IPs, including certificate SAN and `leader_tls_servername` behavior, before starting nodes.

## Decision: Provide private Vault nodes with same-AZ NAT and AWS service endpoints.

Vault nodes require outbound access to the HashiCorp RPM and OS repositories, KMS for auto-unseal, and EC2 APIs for Raft peer discovery. Keep nodes in private subnets without public IPs. Use one NAT Gateway per AZ for general HTTPS repository egress and KMS/EC2 interface VPC endpoints in each AZ for private AWS API access. Private subnet default routes target only the NAT Gateway in their own AZ; endpoint security groups accept HTTPS only from the Vault-node security group.

### Alternatives Considered

- No egress, with packages pre-baked into reviewed AMIs and no runtime AWS API endpoints.
- One shared NAT Gateway for lower cost, accepting cross-AZ dependency and transfer charges.
- A controlled internal RPM mirror or egress proxy instead of unrestricted public HTTPS through NAT.

### Why

- Supports package installation and updates while keeping Vault instances private.
- Keeps KMS and EC2 API traffic on AWS private connectivity where endpoints are used.
- Same-AZ NAT routing avoids depending on another AZ for general egress.

### Consequences

- Three NAT Gateways and two interface endpoint services (KMS and EC2, each with endpoint network interfaces in all three AZs) add recurring cost; review estimates before apply.
- Security-group HTTPS egress through NAT is not destination-domain filtering. Use an internal mirror or egress control if public HTTPS needs tighter restriction.
- Earlier package tests used a public instance in another VPC; the operator subsequently reported successful installation on one private node. This does not validate egress across every AZ or actual Vault KMS seal operations.
- Three NAT Gateways, Elastic IPs, same-AZ private routes, and Vault outbound TCP 443 are implemented. KMS/EC2 interface endpoints are not implemented; AWS API HTTPS currently uses NAT. Endpoints are a planned private-connectivity improvement, not a prerequisite for the current NAT-backed SSM test. Review their plan and cost impact before adding them.
