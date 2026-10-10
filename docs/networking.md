# Networking

## Design

The internet-facing Network Load Balancer uses one public subnet in each of three Availability Zones. Public subnet route tables send internet-bound traffic to the VPC Internet Gateway. Vault nodes remain in private subnets with no direct internet route or public IP assignment.

The public subnets are reserved for the load balancer; EC2 instances launched there do not receive automatic public IPv4 addresses. The NLB is the intended public entry point. NAT Gateways are separate and are not required for inbound NLB traffic.

## Vault target group

The NLB uses an instance target group on TCP port 8200 for Vault's API. Its HTTPS health check requests `/v1/sys/health?standbyok=true` on the target port and accepts only HTTP 200. This is intended to include active and unsealed standby nodes, while excluding sealed or uninitialized nodes. It assumes the Vault listener uses TLS. The target group alone does not connect a listener or register any Vault nodes.

After Vault nodes are registered, verify health and test client requests to both active and standby nodes. Vault forwarding or redirects from standbys must not expose an unreachable private node address to public clients. NLB may fail open if every target is unhealthy, so health checks do not replace Vault-side access controls or readiness validation.

## Security and failure behavior

The network-security module defines two security groups:

| Group       | Inbound                                                                        | Outbound                                                       |
| ----------- | ------------------------------------------------------------------------------ | -------------------------------------------------------------- |
| NLB         | TCP 443 from the internet                                                      | TCP 8200 to the private Vault subnet CIDRs                     |
| Vault nodes | TCP 8200 from the NLB group; TCP 8200/8201 from other nodes in the Vault group | TCP 8200/8201 to nodes in the Vault group; TCP 443 through NAT |

Port 8200 carries Vault API and peer API traffic; port 8201 carries cluster traffic. Vault nodes have no public IPs or direct internet route. Outbound HTTPS uses same-AZ NAT; private KMS/EC2 endpoints remain planned. Administrative SSH uses an SSM tunnel rather than inbound TCP 22; SSM requires outbound access to its service endpoints.

The NLB has no listener yet. The launch template attaches the Vault group, and the ASG registers instances with the target group. Registration is not healthy service: the installation role stops Vault, and no live NLB/Vault health validation has been recorded. The planned listener is TCP 443 pass-through to Vault on TCP 8200; Vault presents the client certificate, and the NLB does not decrypt API traffic. AZ failure behavior must be tested once the cluster serves requests. If every target is unhealthy, the NLB may fail open; health checks are not an access-control boundary.

## Validation

Before applying changes, run `terraform fmt -check`, `terraform validate`, and `terraform plan`. Review changes to the VPC, subnets, routes, NLB, target group, and security groups. Verify the NLB security-group attachment after apply; test client and peer traffic when listeners and nodes exist.

## Outbound access

### Design for Vault nodes

Vault ASG instances launch in private subnets. Three per-AZ NAT Gateways and Elastic IPs are implemented in the matching public subnets, and each private subnet has a default route through its same-AZ NAT. Earlier RPM tests used a separate public host; subsequently, the operator reported successful Vault installation on one private node through laptop Ansible over SSM. This exercises that node's repository access, not all three AZs or actual Vault KMS operations.

Provide private AWS API access using interface VPC endpoints for KMS and EC2 in all three Vault AZs, with private DNS enabled. The endpoint security group should accept TCP 443 only from the Vault-node security group; Vault-node egress should allow TCP 443 to those endpoint security groups. This supports KMS auto-unseal and AWS Raft peer discovery without routing those AWS API calls through the public internet.

For the pinned Vault RPM and operating-system repositories, use one NAT Gateway per AZ in the corresponding public subnet. Each private subnet has its own route table; its `0.0.0.0/0` route targets the NAT Gateway in the same AZ. Keep Vault instances without public IPs. The Vault security group allows outbound TCP 443 to `0.0.0.0/0` for repository access; NAT provides the route but does not itself grant security-group permission. Security groups cannot filter by DNS name, so this rule permits HTTPS to public IPv4 destinations generally. Use an internal repository mirror or egress proxy/firewall if stricter destination control is required.

This three-AZ layout avoids making one AZ's NAT a dependency for all Vault nodes, but NAT Gateways and interface endpoints have recurring hourly and data-processing charges. A shared NAT or privately mirrored package can reduce development cost but changes the availability, traffic, or operational trade-offs. The NAT Gateways and private routes are deployed and incur charges. KMS/EC2 interface endpoints are not implemented; until then, HTTPS to those public AWS APIs would also traverse NAT. Add an S3 gateway endpoint with a restricted bucket policy during the snapshot-backup stage.
