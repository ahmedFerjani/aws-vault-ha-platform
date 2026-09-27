# Networking

## Design

The internet-facing Network Load Balancer uses one public subnet in each of three Availability Zones. Public subnet route tables send internet-bound traffic to the VPC Internet Gateway. Vault nodes remain in private subnets with no direct internet route or public IP assignment.

The public subnets are reserved for the load balancer; EC2 instances launched there do not receive automatic public IPv4 addresses. The NLB is the intended public entry point. NAT Gateways are separate and are not required for inbound NLB traffic.

## Security and failure behavior

The Internet Gateway provides a route, not permission to access a resource. Security groups and the NLB listener will control traffic when those resources are implemented. Vault API access must use TLS, and Vault nodes must accept client traffic only from the NLB.

Each AZ has its own public subnet and route to the Internet Gateway, avoiding a single-AZ subnet dependency for the NLB. Loss of an AZ still reduces available NLB capacity; the other AZs remain available.

## Validation

Before applying changes, run `terraform fmt -check`, `terraform validate`, and `terraform plan`. Confirm the plan preserves the existing VPC and private subnets and only adds the public networking resources. After apply, verify the Internet Gateway attachment, public route table associations, and one public subnet per AZ.

## Outbound access

Private-subnet egress is a separate decision. Use VPC endpoints for required AWS services where practical. Add one NAT Gateway per AZ only if Vault nodes require general internet egress, such as reaching public package repositories; account for its recurring cost.
