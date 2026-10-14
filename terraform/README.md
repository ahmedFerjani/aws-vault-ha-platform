# Terraform

This directory contains the AWS infrastructure layer for the Vault platform.

## Current milestone

Infrastructure and single-node installation foundations are implemented. Terraform owns AWS resources; Ansible owns node configuration. The current controller is the laptop using SSH over SSM, not a management EC2 host.

### Implemented components

- VPC and three public/private subnet pairs in `us-east-1`
- Internet Gateway, route tables, and one NAT Gateway/EIP per AZ
- NLB and TCP 8200 instance target group with Vault HTTPS health checks
- Restrictive NLB/Vault security groups, no inbound SSH, and outbound HTTPS
- Auto-unseal KMS key with rotation, 30-day deletion window, and `prevent_destroy`
- Separate recovery KMS key and empty Secrets Manager recovery-bundle secret, both protected from ordinary destruction
- Vault EC2 role with key-scoped KMS permissions and SSM registration permissions
- Private launch template with IMDSv2 and encrypted EBS
- ASG with minimum 0, desired 1, maximum 3, and target-group registration

### Not yet implemented or validated

No NLB listener, Route 53 alias, KMS/EC2 interface endpoints, or S3 backup infrastructure is implemented. AWS Raft discovery, safe replacement bootstrap, three-node HA, and runtime KMS auto-unseal remain pending. The ASG is not a completed stateful replacement solution. SSH public-key authorization is still manual; refresh inventory and verified host keys after each node replacement. See [installation instructions](../docs/vault-installation.md).

The recovery bundle secret contains no value; Terraform manages only its metadata and the dedicated encryption key. Root outputs expose the non-secret secret name/ARN and recovery KMS key ARN. A dedicated bootstrap IAM role and one-time Ansible/Python bootstrap are not implemented yet. Do not apply the recovery-resource plan until IAM trust and usage permissions are designed and reviewed.

### Validation approach

Run `terraform fmt -check`, `terraform validate`, and `terraform plan` from this directory. These checks validate Terraform configuration and planned infrastructure changes; they do not validate Vault runtime behavior.

Review every plan before applying, including replacement, IAM, network exposure, and recurring costs. Never terminate multiple Raft nodes automatically; a three-node cluster requires two for quorum. Do not use ASG capacity changes as an unattended shutdown procedure for initialized Vault. Protect state as sensitive data and preserve required snapshots and the original seal key before teardown. The KMS key's `prevent_destroy` intentionally blocks ordinary Terraform destruction of that key; do not remove the safeguard merely to make destroy succeed. NAT Gateways, EIPs, and the NLB incur costs even while Vault is stopped.
