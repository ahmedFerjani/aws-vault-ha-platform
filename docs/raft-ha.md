# Raft HA design and validation plan

## Status and scope

**Single-node milestone complete; Raft HA remains in progress.** The operator reports Vault 2.1.1 initialized with five recovery shares and a threshold of three; the recovery bundle was stored in Secrets Manager. `vault status` reported initialized and unsealed after a controlled restart, providing initial single-node auto-unseal evidence. The NLB TCP 443 listener and Route 53 alias were applied; the target became healthy and an HTTPS health request through the NLB succeeded. These are operator-reported results, not a current live-state check.

The ASG desired capacity is one. No follower has joined, so there is no three-node quorum or HA yet. AWS discovery/`retry_join` configuration is present but has not been runtime-tested by adding a follower. Standby forwarding, cross-zone behavior, leader election, quorum-loss recovery, and replacement remain unvalidated. S3 snapshot/restore is not implemented. Keep the service disabled at boot unless/until a separate boot/restart policy is deliberately approved. Do not run the deployment playbook against this initialized serving node: the role stops and disables Vault.

The target architecture is three Vault OSS nodes across three AZs using Raft Integrated Storage. Three voters require quorum two: one unavailable voter is tolerated; losing two makes normal quorum-dependent operations unavailable. Raft stores live Vault state on each node's encrypted EBS. AWS KMS provides auto-unseal, not storage. S3 snapshots are a planned backup mechanism, not live storage.

## Addressing model

These addresses serve distinct roles:

- Listener `address`: each Vault process binds its API listener on TCP 8200 on the node interfaces.
- Listener `cluster_address`: each process binds its peer listener on TCP 8201 on the node interfaces.
- Top-level `cluster_addr`: advertise that node's private IP and port 8201 so Vault peers can reach it directly.
- Top-level `api_addr`: advertise the client URL. The configuration selects the shared endpoint `https://vault.ahmedferjani.com:443`; the TCP 443 listener and Route 53 alias are applied, and the operator reports a successful single-node HTTPS health request through the NLB. Multi-node redirects/forwarding remain untested.

`api_addr` is not a bind address. `cluster_addr` is per-node and must never be the public NLB address. The Ansible template sets the shared NLB hostname in `api_addr` and derives private `cluster_addr` from the node address.

## NLB and client-routing behavior

The NLB is Layer 4 TCP pass-through: public TCP 443 forwards to Vault API TCP 8200; Vault terminates TLS with a certificate valid for `vault.ahmedferjani.com`. Port 8201 remains private and is never exposed through the NLB.

The current target group uses `/v1/sys/health?standbyok=true` with an HTTP 200 matcher. This is intended to mark initialized, unsealed active and standby nodes healthy while excluding sealed/uninitialized nodes. The operator reports the single target healthy and a successful HTTPS health request through the NLB. Cross-zone routing and this behavior across multiple nodes still require verification against the deployed NLB and Vault 2.1.1.

### Known trade-off and required validation

All nodes share the NLB `api_addr`. Standbys normally forward requests to the leader, but redirect fallback or leader-election races could send clients back through the NLB and potentially loop. Test forwarding, redirects, and retries after followers join.

An active-only health check may reduce standby selection but can leave no healthy targets during elections. NLB fail-open can still forward to unhealthy targets, so this is a trade-off rather than a complete fix. Keep the current policy until tested evidence supports a change.

NLB health checks are not access control: AWS can fail open when all targets are unhealthy. Vault must safely reject requests while sealed/uninitialized. Validate target health and client behavior before declaring HA.

## Raft joining and peer TLS

### AWS discovery tag and IAM

Terraform tags future launch-template instances with `VaultCluster = var.name_prefix` (currently `vault-ha-dev`). The tag must be on each EC2 instance, not only its volume. The operator also tagged the running first node; AWS inspection confirmed `VaultCluster=vault-ha-dev` and SSM Online. The tag is the discovery filter, not an IAM authorization boundary.

Vault's AWS `go-discover` provider takes `provider=aws`, `region`, `tag_key`, `tag_value`, and `addr_type` (the provider's option spelling is `addr_type`). It filters for running EC2 instances and returns their private addresses. The configured setting is:

```hcl
retry_join {
	auto_join             = "provider=aws region=us-east-1 tag_key=VaultCluster tag_value=vault-ha-dev addr_type=private_v4"
	auto_join_scheme      = "https"
	auto_join_port        = 8200
	leader_tls_servername = "vault.ahmedferjani.com"
	leader_ca_cert_file   = "/etc/pki/tls/certs/ca-bundle.crt"
}
```

The operator reports the `retry_join` configuration was deployed and the rendered HCL contains AWS private-IPv4 discovery, HTTPS API join on port 8200, the certificate SAN as `leader_tls_servername`, and the Amazon Linux CA bundle. No follower has been launched or joined, so AWS discovery/TLS join has not been runtime-tested. Preserve the existing Raft data files; a follower must join the initialized cluster rather than initialize independently.

The discovery call needs only `ec2:DescribeInstances`. AWS does not support resource-level scoping for that action, so the policy must use `Resource = "*"`; AWS documents the `ec2:Region` condition key for restricting EC2 actions to `us-east-1`. Do not claim that the request's tag filters enforce IAM authorization: they filter discovery results, not the scope of the permission. The role can describe instances in the allowed region, but Vault's discovery request will use the dedicated tag. No `RunInstances`, `CreateTags`, stop, or terminate permissions are needed for discovery.

Discovery finds join candidates but does not preserve Raft identity or membership: a replacement must join the existing cluster, never initialize a separate one.

### TLS during join

AWS discovery returns private IPs, while the server certificate identifies `vault.ahmedferjani.com`. At join time Vault contacts the candidate API on HTTPS/TCP 8200; `leader_tls_servername` selects the certificate SAN to verify and `leader_ca_cert_file` supplies trusted roots. The CA bundle path was checked on the current node. Do not disable certificate verification. After joining, peer/Raft traffic uses private TCP 8201 with Vault's cluster mTLS credentials. The Vault security group allows peer TCP 8200 and 8201 between group members.

## First-node initialization and lifecycle

Initialize exactly one confirmed-empty node. Under KMS auto-unseal, Vault returns recovery shares rather than ordinary unseal keys; recovery shares do not replace the auto-unseal key. Preserve the original KMS key and protect the init output.

Terraform creates a separate recovery KMS key, empty Secrets Manager secret, and scoped bootstrap role; it never manages secret values. The Ansible bootstrap playbook runs preflight, checks that Vault is uninitialized, prompts, initializes 5 shares with threshold 3, and pipes the captured JSON to the controller-side helper. The helper stores one bundle containing all shares and the initial root token. Vault EC2 roles cannot read this secret. The operator workflow and exact commands are in [vault-installation.md](vault-installation.md#one-time-vault-initialization-and-recovery-storage).

Assume one authorized bootstrap operator at a time; there is no distributed lock. Initialization and secret storage are not atomic, and the response is held only in controller memory. If it is lost after initialization, never rerun init and do not assume Vault can reveal the original shares or root token. Stop and assess recovery options; without a recovery quorum, valid administrative access, or usable backup, the data may be unrecoverable.

## Remaining implementation and validation sequence

1. Review cross-zone routing and validate NLB health/forwarding on the current one-node service. This is a smoke test, not HA.
2. Increase ASG capacity deliberately, one follower at a time. Confirm each joins the existing cluster; verify peers, AZs, seal state, and health after each join. Never initialize followers independently.
3. With three healthy members, test standby forwarding, redirects/fallback, leader election, target-health convergence, and client retries through the stable endpoint.
4. Run controlled node/quorum failure and replacement tests with recovery evidence. Add snapshot/restore validation as a separate backup/DR stage.

Initialization, ASG capacity changes, node termination, and Raft membership changes are stateful operations and require review. Completed items are operator-reported; remaining HA behavior needs live validation.
