# Networking

## Design

The internet-facing NLB spans three public subnets and routes through the Internet Gateway. Vault nodes stay in private subnets without public IPs or direct internet routes. NAT is for node egress, not inbound NLB traffic.

## Vault target group

The instance target group forwards TCP 8200 and checks HTTPS `/v1/sys/health?standbyok=true`, accepting HTTP 200. This is intended to include active/unsealed standby nodes and exclude sealed or uninitialized nodes. The TCP 443 listener passes TLS through to Vault; the ASG registers instances.

The operator reports the single target became healthy and an HTTPS health request succeeded through the NLB. Test standby forwarding/redirects after adding followers. NLB may fail open when all targets are unhealthy, so health checks are not an access-control boundary.

## Security and failure behavior

The network-security module defines two security groups:

| Group       | Inbound                                                                        | Outbound                                                       |
| ----------- | ------------------------------------------------------------------------------ | -------------------------------------------------------------- |
| NLB         | TCP 443 from the internet                                                      | TCP 8200 to the private Vault subnet CIDRs                     |
| Vault nodes | TCP 8200 from the NLB group; TCP 8200/8201 from other nodes in the Vault group | TCP 8200/8201 to nodes in the Vault group; TCP 443 through NAT |

Port 8200 carries API/peer API traffic; 8201 carries cluster traffic. Nodes use same-AZ NAT for HTTPS. KMS/EC2 interface endpoints are deferred. Administration uses SSH-over-SSM, not inbound TCP 22.

The TCP 443 listener and `vault.ahmedferjani.com` alias are applied. Single-node HTTPS health passed per operator report. Cross-zone routing, leader transitions, and AZ-failure behavior require multi-node testing.

## Validation

Before networking changes, run `terraform fmt -check`, `terraform validate`, and `terraform plan`; review network exposure and cost. Recheck target health and client/peer routing as followers join.

## Outbound access and cost

Vault nodes have no public IPs. Each private subnet routes HTTPS through its same-AZ NAT Gateway; the security group allows TCP 443 to public IPv4 destinations, not just named repositories. Three NAT Gateways/EIPs incur ongoing charges. A shared NAT or internal mirror can reduce lab cost with availability/operations trade-offs. KMS/EC2 interface endpoints are deferred; an S3 gateway endpoint belongs in the future snapshot-backup design.
