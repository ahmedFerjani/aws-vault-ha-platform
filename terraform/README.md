# Terraform

This directory contains the AWS infrastructure layer for the Vault platform.

## Current milestone

Infrastructure and single-node installation foundations are implemented. Terraform owns AWS resources; Ansible owns node configuration. The current controller is the laptop using SSH over SSM, not a management EC2 host.

### Implemented components

- VPC and three public/private subnet pairs in `us-east-1`
- Internet Gateway, route tables, and one NAT Gateway/EIP per AZ
- Internet-facing NLB, TCP 8200 instance target group/HTTPS health checks, TCP 443 pass-through listener, and Route 53 alias
- Restrictive NLB/Vault security groups, no inbound SSH, and outbound HTTPS
- Auto-unseal KMS key with rotation, 30-day deletion window, and `prevent_destroy`
- Separate recovery KMS key, Secrets Manager recovery-bundle secret, and scoped bootstrap IAM role
- Vault EC2 role with key-scoped KMS permissions and SSM registration permissions
- Private launch template with IMDSv2 and encrypted EBS
- ASG with minimum 0, desired 1, maximum 3, and target-group registration

### Not yet implemented or validated

Three-node Raft membership, leader/quorum failure handling, automated node replacement, KMS/EC2 interface endpoints, S3 backup infrastructure, and restore testing remain incomplete. The ASG is not a safe stateful replacement solution. Ansible playbooks are the operator entry points for SSM access preparation, one-node deployment, and one-time bootstrap; see [installation instructions](../docs/vault-installation.md). The recovery secret is populated only by the bootstrap workflow; Terraform manages metadata, never its secret value.

### Validation approach

Run `terraform fmt -check`, `terraform validate`, and `terraform plan` from this directory. These checks validate Terraform configuration and planned infrastructure changes; they do not validate Vault runtime behavior.

Review every plan before applying, including replacement, IAM, network exposure, and recurring costs. Never terminate multiple Raft nodes automatically; a three-node cluster requires two for quorum. Do not use ASG capacity changes as an unattended shutdown procedure for initialized Vault. Protect state as sensitive data and preserve required snapshots and the original seal key before teardown. The KMS key's `prevent_destroy` intentionally blocks ordinary Terraform destruction of that key; do not remove the safeguard merely to make destroy succeed. NAT Gateways, EIPs, and the NLB incur costs even while Vault is stopped.
