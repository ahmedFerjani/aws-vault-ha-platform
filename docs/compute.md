# Compute

## Design

The Vault nodes will use an EC2 launch template and, later, an Auto Scaling Group spread across the three private subnets. This step creates only the launch template; it does not launch instances.

The template uses the Amazon Linux 2023 x86_64 AMI ID published through AWS Systems Manager Parameter Store, the Vault-node instance profile and security group, and a `t3.medium` starter size for this learning environment. Review and pin a tested AMI version for controlled production rollouts; the public `latest` parameter can change over time.

Require IMDSv2, disable public IPv4 assignment, and use an encrypted 20 GiB gp3 root volume deleted with the instance. No SSH key or user data is configured. Ansible installation and deterministic Vault bootstrap are separate work; design bootstrap and Raft join behavior before creating an ASG or launching nodes.

## Security and operations

The launch template attaches the existing least-privilege instance profile and Vault-node security group. The profile provides temporary role credentials; it does not create a network path to KMS. No Vault node may receive a public IP.

Replacing a Vault instance is stateful: a replacement must install and configure Vault, discover the existing cluster, join Raft, and become healthy without initializing an independent cluster. Do not enable automatic replacement until that flow is designed and tested.

## Validation

Run `terraform fmt -check`, `terraform validate`, and `terraform plan`. Confirm only the launch template is added and that it references the intended AMI, instance profile, private-node security group, IMDSv2, and encrypted root volume. No instance or Vault behavior is validated by creating a launch template.
