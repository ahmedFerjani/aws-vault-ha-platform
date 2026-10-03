# Compute

## Design

The Vault nodes use an EC2 launch template and an Auto Scaling Group spanning the three private subnets. Desired and minimum capacities are zero until Stage 4 installation and safe Raft bootstrap are implemented and tested. The maximum capacity is three to avoid uncontrolled Vault scaling. A temporary EC2/ASG smoke test launched one billable, bare Amazon Linux instance; Vault was not installed.

The template uses a pinned Amazon Linux 2023 x86_64 AMI ID for `us-east-1`, the Vault-node instance profile and security group, and a `t3.medium` starter size for this learning environment. The AMI ID is an explicit root input so plans are reproducible rather than following a moving `latest` parameter. The currently pinned image came from that parameter but has not been validated by launching and testing a Vault node. Review and test a replacement AMI before updating the pin; AMI IDs are region-specific.

Require IMDSv2, disable public IPv4 assignment, and use an encrypted 20 GiB gp3 root volume deleted with the instance. No SSH key or user data is configured. Ansible installation and deterministic Vault bootstrap are separate work; design bootstrap and Raft join behavior before creating an ASG or launching nodes.

## Security and operations

The launch template attaches the existing least-privilege instance profile and Vault-node security group. The profile provides temporary role credentials; it does not create a network path to KMS. No Vault node may receive a public IP. The current template has no SSH key, Session Manager permissions/connectivity, or bootstrap, so the smoke test is limited to EC2/ASG state visible in AWS; the instance cannot be interactively managed through those methods and is not a functioning Vault target. An unhealthy target is expected until Vault is installed and configured.

Replacing a Vault instance is stateful: a replacement must install and configure Vault, discover the existing cluster, join Raft, and become healthy without initializing an independent cluster. Before scaling above zero, verify the ASG can distribute instances across AZs and that one-node replacement preserves quorum. Never allow automated replacement to initialize an independent cluster.

## Validation

Run `terraform fmt -check`, `terraform validate`, and `terraform plan`. Confirm the launch template retains the pinned AMI, instance profile, private-node security group, IMDSv2, and encrypted root volume. Confirm the ASG spans only private subnets and has zero desired capacity. The temporary smoke test verified EC2/ASG provisioning only, not Vault behavior or target health.
