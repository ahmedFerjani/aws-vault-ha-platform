# Compute and node operations

## Terraform implementation

Terraform provisions a launch template and ASG across three private subnets. Capacity is min 0, desired 1, max 3, so the current deployment is single-node. The ASG registers nodes with the NLB target group; TCP 443 and the DNS alias are configured.

The launch template uses pinned Amazon Linux 2023, `t3.medium`, the Vault instance profile/security group, IMDSv2, no public IPv4, and an encrypted 20 GiB gp3 root volume deleted at termination. It uses no EC2 key pair or user data.

Terraform owns AWS resources. Ansible installs Vault, creates its service identity/directories, deploys TLS, and renders configuration. The role deliberately stops and disables Vault; installation alone does not make a healthy target.

## Administrative access

The laptop uses SSH tunneled over SSM. Nodes stay private, with no public IP, management EC2 host, or inbound SSH rule. IAM authorizes SSM, SSH keys authenticate `ec2-user`, and pinned host keys verify node identity. SSM does not record SSH command contents.

The operator entry points are Ansible playbooks documented in [vault-installation.md](vault-installation.md): access preparation, single-node deployment, and one-time bootstrap. The access playbook invokes a local helper through SSM Run Command. Automated ASG replacement and rejoining initialized nodes remain separate, unimplemented capabilities.

## Stateful operation and safety

Vault is stateful. Three Raft voters need two for quorum; losing two removes it. ASG is not a safe stateful replacement mechanism. A replacement workflow must install/configure a node, discover and TLS-verify the existing cluster, then join without initializing.

Before terminating initialized nodes, review Raft quorum and backups. Root EBS is deleted at termination; preserve the original KMS key because recreating its alias does not restore key material. The key has `prevent_destroy` and a 30-day deletion window. NAT, EIP, NLB, and volumes incur ongoing charges.

## Current checkpoint

The operator reports Vault is initialized and stayed unsealed after a controlled restart. The service remains disabled at boot and will not start automatically after reboot. The cluster currently has one node; see [raft-ha.md](raft-ha.md) for endpoint validation and remaining HA work. Recheck current state before operating.
