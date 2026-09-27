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
