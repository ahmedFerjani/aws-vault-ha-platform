# Raft HA design proposal

## Status and scope

**Implementation in progress; cluster behavior not validated.** The current ASG requests one private node. Ansible installs/configures Vault and deliberately leaves the service stopped and disabled. The cluster has not been initialized. Do not initialize it or increase ASG capacity as part of this design step.

## Current single-node preflight

Read-only inspection on 2026-10-13 confirmed the current ASG desired capacity is one and its instance is `InService`/healthy with SSM Online. Vault 2.1.1 is installed; before startup the Raft data directory had no entries. Startup has since created `node-id`, `vault.db`, and `raft/raft.db` while Vault remains uninitialized. Preserve these files; uninitialized does not mean the data directory is empty. The configuration, TLS, and environment-file ownership/modes match the Ansible role; the certificate SAN is `vault.ahmedferjani.com`. The AWS KMS alias resolves to an enabled `ENCRYPT_DECRYPT` key. This is metadata evidence, not a KMS operation by Vault.

Terraform apply added the region-limited `ec2:DescribeInstances` permission and `VaultCluster=vault-ha-dev` to the latest launch-template version without replacing the current node. The operator then tagged the current ASG instance; read-only AWS inspection confirmed it has `VaultCluster=vault-ha-dev` and remains SSM Online. The launch-template tag covers future instances.

The current rendered HCL advertises `https://vault.ahmedferjani.com:443` as `api_addr`; `cluster_addr` remains this node's private IP on 8201. The operator verified both values after Ansible deployment. Vault is currently inactive and disabled at boot. The NLB listener and DNS alias are not implemented, so the advertised client endpoint is not reachable or runtime-validated yet.

Ansible check-mode preview showed only the expected `api_addr` change; the guarded deployment applied it. The operator verified the resulting address values.

Controlled startup test on 2026-10-13: systemd started Vault successfully while the unit remained disabled at boot. A local curl used the certificate hostname with explicit loopback resolution and normal certificate verification; it returned HTTP 501 with `initialized:false`, `sealed:true`, and Vault 2.1.1. This validates the local TLS listener and expected uninitialized health response. It does not exercise KMS seal operations, NLB/DNS, initialization, or Raft. Vault is currently running but uninitialized on this single node; do not initialize until secure output handling and follower-join prerequisites are resolved.

Public endpoint preflight on 2026-10-13: the internet-facing NLB is active but has no listeners; its target is `unused`/`Target.NotInUse` because no listener uses the target group. Route 53 has no `vault.ahmedferjani.com` record, and a normal public HTTPS request could not resolve the hostname. Do not add a public listener while Vault is uninitialized: the initialization endpoint is unauthenticated by design. After the first node is initialized and KMS auto-unseal is validated, a temporary single-node public endpoint test is possible before joining followers. Treat that interval as explicitly non-HA; expect downtime during any single-node restart.

The target is three Vault OSS nodes across three AZs using Raft Integrated Storage. Three voters require quorum of two: one unavailable voter is tolerated; losing two makes normal quorum-dependent operations unavailable. Raft stores live Vault state on each node's encrypted EBS. AWS KMS is the auto-unseal mechanism, not storage. S3 snapshots are the planned backup mechanism, not live storage.

## Addressing model

These addresses serve distinct roles:

- Listener `address`: each Vault process binds its API listener on TCP 8200 on the node interfaces.
- Listener `cluster_address`: each process binds its peer listener on TCP 8201 on the node interfaces.
- Top-level `cluster_addr`: advertise that node's private IP and port 8201 so Vault peers can reach it directly.
- Top-level `api_addr`: advertise the client URL. The configuration now selects the shared endpoint `https://vault.ahmedferjani.com:443` on every node because clients are intended to reach Vault only through the NLB; the listener, DNS alias, and runtime redirect path are not yet implemented or tested.

`api_addr` is not a bind address. `cluster_addr` is per-node and must never be the public NLB address. The Ansible template sets the shared NLB hostname in `api_addr` and derives private `cluster_addr` from the node address.

## Proposed NLB and client-routing behavior

The NLB is Layer 4 TCP pass-through: public TCP 443 forwards to Vault API TCP 8200; Vault terminates TLS with a certificate valid for `vault.ahmedferjani.com`. Port 8201 remains private and is never exposed through the NLB.

**Recommendation for the first HA iteration:** keep the current `/v1/sys/health?standbyok=true` health check and HTTP 200 matcher. This marks initialized, unsealed active and standby nodes healthy, while sealed/uninitialized nodes do not pass. Enable and verify NLB cross-zone routing so a healthy target in any AZ can receive traffic. Vault normally forwards requests received by an unsealed standby to the active node, so clients can use the stable NLB endpoint while the leader moves. Cross-zone configuration and this health-check behavior still require review against the deployed NLB and Vault 2.1.1.

### Known trade-off and required validation

With only the NLB reachable by clients, all nodes share the same `api_addr`. HashiCorp documents that redirect fallback can send a client from a standby back to the same load balancer and potentially to another standby. Normal Vault request forwarding is expected to handle requests, but fallback redirects and leader-election races must be tested; do not claim they cannot loop.

An alternative is an active-only target health check. That reduces normal standby selection and redirect risk, but leaves the NLB without healthy targets during startup/elections until health checks converge. NLB fail-open behavior can then send requests to unhealthy nodes anyway. This trades routine standby forwarding for greater dependence on health-check convergence and does not remove transient failure risk. Do not switch to active-only health implicitly; revisit the design if the shared-endpoint forwarding tests fail.

AWS NLB fails open when all targets are unhealthy (and for an empty target group), so health checks are not an access-control boundary. Vault itself must safely reject requests while sealed or uninitialized. Test real health responses, target health, forwarded requests, redirect fallback, and leader changes before declaring client availability.

## Raft joining and peer TLS

### AWS discovery tag and IAM

Terraform tags future launch-template instances with `VaultCluster = var.name_prefix` (currently `vault-ha-dev`). The tag must be on each EC2 instance, not only its volume. The operator also tagged the running first node; AWS inspection confirmed `VaultCluster=vault-ha-dev` and SSM Online. The tag is the discovery filter, not an IAM authorization boundary.

Vault's AWS `go-discover` provider takes `provider=aws`, `region`, `tag_key`, `tag_value`, and `addr_type` (the provider's option spelling is `addr_type`). It filters for running EC2 instances and returns their private addresses. The proposed setting is:

```hcl
retry_join {
	auto_join             = "provider=aws region=us-east-1 tag_key=VaultCluster tag_value=vault-ha-dev addr_type=private_v4"
	auto_join_scheme      = "https"
	auto_join_port        = 8200
	leader_tls_servername = "vault.ahmedferjani.com"
	leader_ca_cert_file   = "/etc/pki/tls/certs/ca-bundle.crt"
}
```

The guarded Ansible deployment applied the `retry_join` block and completed `ok=16 changed=2 unreachable=0 failed=0`. Read-only verification confirmed the live HCL contains AWS private-IPv4 discovery, HTTPS API join on port 8200, the certificate SAN as `leader_tls_servername`, and the readable Amazon Linux CA bundle. The role left Vault inactive and disabled. Startup-created Raft files (`node-id`, `vault.db`, `raft/raft.db`, and the snapshots directory) remain; preserve them. The node is still uninitialized; no follower has been launched or joined, and AWS discovery/TLS join has not been runtime-tested.

The discovery call needs only `ec2:DescribeInstances`. AWS does not support resource-level scoping for that action, so the policy must use `Resource = "*"`; AWS documents the `ec2:Region` condition key for restricting EC2 actions to `us-east-1`. Do not claim that the request's tag filters enforce IAM authorization: they filter discovery results, not the scope of the permission. The role can describe instances in the allowed region, but Vault's discovery request will use the dedicated tag. No `RunInstances`, `CreateTags`, stop, or terminate permissions are needed for discovery.

Discovery finds join candidates but does not preserve Raft identity or membership: a replacement must join the existing cluster, never initialize a separate one.

### TLS during join

AWS discovery returns private IPs, while the server certificate identifies `vault.ahmedferjani.com`. At join time Vault contacts the candidate API on HTTPS/TCP 8200; `leader_tls_servername` selects the certificate SAN to verify and `leader_ca_cert_file` supplies trusted roots. The CA bundle path was checked on the current node. Do not disable certificate verification. After joining, peer/Raft traffic uses private TCP 8201 with Vault's cluster mTLS credentials. The Vault security group allows peer TCP 8200 and 8201 between group members.

## First-node initialization and lifecycle

Initialization is a one-time stateful operation on exactly one confirmed-empty node. Decide secure handling of recovery keys and the initial root token before running `vault operator init`; do not put output in Git, Terraform state, ordinary automation logs, shell history, or ephemeral instance storage. With KMS auto-unseal, initialization produces recovery keys; they do not replace the KMS key and do not manually unseal Vault. Preserve the original KMS key if initialized data must be recovered.

### Recovery secret infrastructure — iteration 1 design

The recovery storage foundation is a dedicated KMS key and one empty Secrets Manager secret named `${name_prefix}/bootstrap-recovery`. The recovery key is separate from Vault's auto-unseal key. Terraform creates only the secret container and metadata; no root token, recovery key, `SecretString`, generated credential, or Vault initialization data enters Terraform state.

The key and secret receive deletion protection (`prevent_destroy`) and a 30-day KMS key deletion window. The secret is encrypted with that key. The Terraform module also creates a bootstrap role trusted by the configured deployment IAM principal, with write/metadata access scoped to this secret and KMS use constrained to Secrets Manager and this secret's encryption context. The Vault EC2 instance role is not granted recovery-secret access.

Terraform outputs expose only the secret name, recovery KMS key ARN, and bootstrap role ARN. These are identifiers, not credentials. The single JSON bundle contains five 3-of-5 recovery shares plus the initial root token. Keeping them together simplifies the lab, but anyone allowed to retrieve the secret obtains both; retrieval must therefore be break-glass only.

Implemented in Terraform source: the `vault_recovery` module creates the dedicated KMS key, alias, empty recovery secret, and bootstrap role. No secret value is configured by Terraform. Apply the module only when needed; KMS and Secrets Manager resources have recurring charges.

### One-time bootstrap helper

The single controller-side helper [bootstrap_vault_init.py](../scripts/vault-bootstrap/bootstrap_vault_init.py) has two operations. `preflight` assumes the Terraform-created role, validates the returned STS identity and account, checks the secret's KMS key, and refuses any existing secret version. Run this before initialization. `store` reads captured init JSON from stdin, checks for exactly five recovery shares, a non-empty root token, and 5-of-3 metadata, writes one JSON bundle, then verifies the exact version ID and `AWSCURRENT` label without reading the secret value back. A deterministic 64-character SHA-256 client token makes an identical retry idempotent; a different or unexpected existing version is rejected.

The helper assumes one authorized operator at a time; there is no distributed lock. The source IAM identity must also be allowed to call `sts:AssumeRole` on the Terraform-created bootstrap role; the role's trust policy alone does not grant that permission. Install `boto3` from `scripts/vault-bootstrap/requirements.txt`. With Terraform outputs available, run preflight from the repository root before initialization:

```bash
python3 -m pip install -r scripts/vault-bootstrap/requirements.txt
python3 scripts/vault-bootstrap/bootstrap_vault_init.py preflight \
	--role-arn "$(terraform -chdir=terraform output -raw vault_bootstrap_role_arn)" \
	--secret-id "$(terraform -chdir=terraform output -raw vault_recovery_secret_name)" \
	--kms-key-arn "$(terraform -chdir=terraform output -raw vault_recovery_kms_key_arn)" \
	--region us-east-1
```

Set `AWS_PROFILE` first if the runner uses a named profile. The helper assumes the bootstrap role using those source credentials. Tests mock STS and Secrets Manager and never contact AWS or Vault. This helper only handles preflight and storage; the separate one-time Ansible bootstrap playbook will run Vault init and pipe its captured JSON into `store` with `no_log`.

Vault init and Secrets Manager storage are not atomic. If init succeeds but the controller loses the response before storing it, never initialize again and do not assume Vault can reveal the original root token or recovery shares. Stop and assess recovery options: if the cluster is operational and an authorized root/admin path exists, recovery keys can be rekeyed and a new root token can be generated using the required quorum; if no recovery quorum or administrative access remains, the initialized data may be unrecoverable without a valid backup. This is a documented residual risk, not something the helper can solve. Python reference clearing is best effort and not secure memory zeroization.

Configure the same join behavior on all nodes, initialize only the designated first node, then start and join followers one at a time. Verify membership and health after each join. Do not initialize followers independently. Keep systemd boot enablement separate until restart and KMS auto-unseal have been validated.

## Safe implementation sequence

1. **Complete:** read-only preflight the current instance. No Raft entries or initialized state were observed before startup.
2. **Complete:** preview and apply the HCL address change; the operator verified rendered `api_addr` and private `cluster_addr`.
3. Review/approve the standby-forwarding target-health and cross-zone NLB policy. The shared NLB `api_addr` is selected architecture; client redirects and fallback behavior need live validation.
4. **Complete:** Terraform discovery IAM/tagging is applied, the current instance has the cluster tag, and the guarded Ansible deployment rendered `retry_join`; Vault is left stopped/disabled. Live discovery and follower joining remain untested.
5. **Complete:** start the first node with boot enablement still disabled; hostname-verified local TLS returned the expected uninitialized/sealed health status.
6. Initialize the first node once using the approved secure procedure; verify initialized/unsealed state. This exercises KMS sealing but not restart auto-unseal.
7. Perform a controlled restart of the single-node lab and verify automatic KMS unseal. Expect temporary service downtime; do not enable boot startup yet.
8. If the operator wants the endpoint smoke test before followers, configure the NLB listener and Route 53 alias now and test the public TLS/API health path. Treat this explicitly as single-node, non-HA service; never expose before initialization.
9. Increase ASG capacity deliberately, one node at a time. Configure and verify each follower joins the existing cluster; confirm peers, AZs, seal state, and health after each join.
10. In the three-node cluster, validate the NLB forwarding/health policy, redirect fallback, target health, and leader election through the stable endpoint.
11. Only after healthy three-node membership, design and run controlled leader/follower/quorum-loss tests with recovery evidence.

Any initialization, ASG capacity change, node termination, or Raft membership change is a reviewed stateful operation. This document is a design proposal, not evidence of implementation or success.
