# Compute

## Design

The Vault nodes will use an EC2 launch template and, later, an Auto Scaling Group spread across the three private subnets. This step creates only the launch template; it does not launch instances.

The template uses a pinned Amazon Linux 2023 x86_64 AMI ID for `us-east-1`, the Vault-node instance profile and security group, and a `t3.medium` starter size for this learning environment. The AMI ID is an explicit root input so plans are reproducible rather than following a moving `latest` parameter. The currently pinned image came from that parameter but has not been validated by launching and testing a Vault node. Review and test a replacement AMI before updating the pin; AMI IDs are region-specific.

Require IMDSv2, disable public IPv4 assignment, and use an encrypted 20 GiB gp3 root volume deleted with the instance. No SSH key or user data is configured. Ansible installation and deterministic Vault bootstrap are separate work; design bootstrap and Raft join behavior before creating an ASG or launching nodes.

## Security and operations

The launch template attaches the existing least-privilege instance profile and Vault-node security group. The profile provides temporary role credentials; it does not create a network path to KMS. No Vault node may receive a public IP.

Replacing a Vault instance is stateful: a replacement must install and configure Vault, discover the existing cluster, join Raft, and become healthy without initializing an independent cluster. Do not enable automatic replacement until that flow is designed and tested.

## Validation

Run `terraform fmt -check`, `terraform validate`, and `terraform plan`. Confirm the launch template retains the pinned AMI, instance profile, private-node security group, IMDSv2, and encrypted root volume. No instance or Vault behavior is validated by creating a launch template.
