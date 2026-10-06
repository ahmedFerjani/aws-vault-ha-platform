# Networking

## Design

The internet-facing Network Load Balancer uses one public subnet in each of three Availability Zones. Public subnet route tables send internet-bound traffic to the VPC Internet Gateway. Vault nodes remain in private subnets with no direct internet route or public IP assignment.

The public subnets are reserved for the load balancer; EC2 instances launched there do not receive automatic public IPv4 addresses. The NLB is the intended public entry point. NAT Gateways are separate and are not required for inbound NLB traffic.

## Vault target group

The NLB uses an instance target group on TCP port 8200 for Vault's API. Its HTTPS health check requests `/v1/sys/health?standbyok=true` on the target port and accepts only HTTP 200. This is intended to include active and unsealed standby nodes, while excluding sealed or uninitialized nodes. It assumes the Vault listener uses TLS. The target group alone does not connect a listener or register any Vault nodes.

After Vault nodes are registered, verify health and test client requests to both active and standby nodes. Vault forwarding or redirects from standbys must not expose an unreachable private node address to public clients. NLB may fail open if every target is unhealthy, so health checks do not replace Vault-side access controls or readiness validation.

## Security and failure behavior

The network-security module defines two security groups:

| Group       | Inbound                                                                        | Outbound                                   |
| ----------- | ------------------------------------------------------------------------------ | ------------------------------------------ |
| NLB         | TCP 443 from the internet                                                      | TCP 8200 to the private Vault subnet CIDRs |
| Vault nodes | TCP 8200 from the NLB group; TCP 8200/8201 from other nodes in the Vault group | TCP 8200/8201 to nodes in the Vault group  |

Port 8200 carries Vault API and peer API traffic; port 8201 carries cluster traffic. Vault nodes have no public IPs or direct internet route. Access to KMS and other required services still needs an egress design before nodes are launched.

The NLB has no listener or registered targets yet, and the Vault group is not attached to instances; client and peer traffic cannot be tested yet. The planned listener is TCP 443 pass-through to the Vault TLS listener on TCP 8200; Vault presents the client certificate, and the NLB does not decrypt API traffic. One AZ failure reduces NLB capacity, while the remaining AZs stay available. If every target is unhealthy, the NLB may fail open; health checks are not an access-control boundary.

## Validation

Before applying changes, run `terraform fmt -check`, `terraform validate`, and `terraform plan`. Review changes to the VPC, subnets, routes, NLB, target group, and security groups. Verify the NLB security-group attachment after apply; test client and peer traffic when listeners and nodes exist.

## Outbound access

Private-subnet egress is a separate decision. Use VPC endpoints for required AWS services where practical. Add one NAT Gateway per AZ only if Vault nodes require general internet egress, such as reaching public package repositories; account for its recurring cost.
