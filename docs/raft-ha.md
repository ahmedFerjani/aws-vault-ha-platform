# Raft HA design proposal

## Status and scope

**Implementation in progress; cluster behavior not validated.** The current ASG requests one private node. Ansible installs/configures Vault and deliberately leaves the service stopped and disabled. The cluster has not been initialized. Do not initialize it or increase ASG capacity as part of this design step.

## Current single-node preflight

Read-only inspection on 2026-10-13 confirmed the current ASG desired capacity is one and its instance is `InService`/healthy with SSM Online. Vault 2.1.1 is installed; the Raft data directory had no entries before startup. The configuration, TLS, Raft, and environment-file ownership/modes match the Ansible role; the node certificate SAN is `vault.ahmedferjani.com`. The AWS KMS alias configured in HCL resolves to an enabled `ENCRYPT_DECRYPT` key. This is key-metadata evidence, not a KMS operation by Vault.

The current rendered HCL advertises `https://vault.ahmedferjani.com:443` as `api_addr`; `cluster_addr` remains this node's private IP on 8201. The operator verified both values after Ansible deployment. Vault is active but disabled at boot. The NLB listener and DNS alias are not implemented, so the advertised client endpoint is not reachable or runtime-validated yet.

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

Use Raft `retry_join` with AWS discovery filtered by a dedicated cluster tag. The launch template must apply that tag. The Vault node role needs only the EC2 discovery permissions required by the selected Vault/go-discover syntax; verify the supported IAM resource scoping before implementation. Discovery finds join candidates but does not preserve Raft identity or membership: a replacement must join the existing cluster, never initialize a separate one.

AWS discovery returns private addresses. The join operation contacts the leader API on TCP 8200 using HTTPS; set `leader_tls_servername` to `vault.ahmedferjani.com`, which is present in the certificate SAN, and retain CA verification. Confirm the exact Vault 2.1.1 `retry_join` syntax and CA source before templating it. Ensure nodes can exchange API traffic on TCP 8200 and cluster traffic on TCP 8201 through the Vault security group. Never disable TLS verification to make discovery/join succeed.

## First-node initialization and lifecycle

Initialization is a one-time stateful operation on exactly one confirmed-empty node. Decide secure handling of recovery keys and the initial root token before running `vault operator init`; do not put output in Git, Terraform state, ordinary automation logs, shell history, or ephemeral instance storage. With KMS auto-unseal, initialization produces recovery keys; they do not replace the KMS key and do not manually unseal Vault. Preserve the original KMS key if initialized data must be recovered.

Configure the same join behavior on all nodes, initialize only the designated first node, then start and join followers one at a time. Verify membership and health after each join. Do not initialize followers independently. Keep systemd boot enablement separate until restart and KMS auto-unseal have been validated.

## Safe implementation sequence

1. **Complete:** read-only preflight the current instance. No Raft entries or initialized state were observed before startup.
2. **Complete:** preview and apply the HCL address change; the operator verified rendered `api_addr` and private `cluster_addr`.
3. Review/approve the standby-forwarding target-health and cross-zone NLB policy. The shared NLB `api_addr` is selected architecture; client redirects and fallback behavior need live validation.
4. Agree on secure initialization-output capture and implement AWS discovery IAM/tagging plus TLS-verified `retry_join` before initializing the cluster.
5. **Complete:** start the first node with boot enablement still disabled; hostname-verified local TLS returned the expected uninitialized/sealed health status.
6. Initialize the first node once using the approved secure procedure; verify initialized/unsealed state. This exercises KMS sealing but not restart auto-unseal.
7. Perform a controlled restart of the single-node lab and verify automatic KMS unseal. Expect temporary service downtime; do not enable boot startup yet.
8. If the operator wants the endpoint smoke test before followers, configure the NLB listener and Route 53 alias now and test the public TLS/API health path. Treat this explicitly as single-node, non-HA service; never expose before initialization.
9. Increase ASG capacity deliberately, one node at a time. Configure and verify each follower joins the existing cluster; confirm peers, AZs, seal state, and health after each join.
10. In the three-node cluster, validate the NLB forwarding/health policy, redirect fallback, target health, and leader election through the stable endpoint.
11. Only after healthy three-node membership, design and run controlled leader/follower/quorum-loss tests with recovery evidence.

Any initialization, ASG capacity change, node termination, or Raft membership change is a reviewed stateful operation. This document is a design proposal, not evidence of implementation or success.
