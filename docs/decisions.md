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
