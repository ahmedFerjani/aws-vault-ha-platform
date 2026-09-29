# Networking

## Design

The internet-facing Network Load Balancer uses one public subnet in each of three Availability Zones. Public subnet route tables send internet-bound traffic to the VPC Internet Gateway. Vault nodes remain in private subnets with no direct internet route or public IP assignment.

The public subnets are reserved for the load balancer; EC2 instances launched there do not receive automatic public IPv4 addresses. The NLB is the intended public entry point. NAT Gateways are separate and are not required for inbound NLB traffic.

## Vault target group

The NLB uses an instance target group on TCP port 8200 for Vault's API. Its HTTPS health check requests `/v1/sys/health?standbyok=true` on the target port and accepts only HTTP 200. This is intended to include active and unsealed standby nodes, while excluding sealed or uninitialized nodes. It assumes the Vault listener uses TLS. The target group alone does not connect a listener or register any Vault nodes.

After Vault nodes are registered, verify health and test client requests to both active and standby nodes. Vault forwarding or redirects from standbys must not expose an unreachable private node address to public clients. NLB may fail open if every target is unhealthy, so health checks do not replace Vault-side access controls or readiness validation.

## Security and failure behavior

The Internet Gateway provides a route, not permission to access a resource. The NLB security group permits inbound TCP 443 from the internet and outbound TCP 8200 only to the private Vault subnet CIDRs. There is no listener yet, so the NLB cannot accept Vault requests. A future TLS listener must use a trusted certificate; a separate Vault-node security group must allow port 8200 only from the NLB security group. The NLB security group alone does not protect the target instances.

AWS does not allow security groups to be added to an NLB that was originally created without one. This NLB already exists without a security group: replacing it will change its DNS name and briefly interrupt access if any clients use it. Review the Terraform plan and explicitly approve replacement before applying; do not assume an in-place update will succeed. The target group and private Vault subnets must be preserved.

Each AZ has its own public subnet and route to the Internet Gateway, avoiding a single-AZ subnet dependency for the NLB. Loss of an AZ still reduces available NLB capacity; the other AZs remain available.

## Validation

Before applying changes, run `terraform fmt -check`, `terraform validate`, and `terraform plan`. Confirm the plan preserves the existing VPC and private subnets and only adds the public networking resources. After apply, verify the Internet Gateway attachment, public route table associations, and one public subnet per AZ.

## Outbound access

Private-subnet egress is a separate decision. Use VPC endpoints for required AWS services where practical. Add one NAT Gateway per AZ only if Vault nodes require general internet egress, such as reaching public package repositories; account for its recurring cost.
