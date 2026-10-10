# Compute

## Design

The Vault nodes use an EC2 launch template and an Auto Scaling Group spanning the three private subnets. The ASG maximum is three to avoid uncontrolled Vault scaling. Desired capacity is temporarily set to one for an EC2/network smoke test; minimum capacity remains zero. This creates a billable, bare Amazon Linux instance. Vault is not installed or configured, so this is not a functioning Vault target. Return desired capacity to zero after the test unless a later documented stage requires a running node.

The template uses a pinned Amazon Linux 2023 x86_64 AMI ID for `us-east-1`, the Vault-node instance profile and security group, and a `t3.medium` starter size for this learning environment. The AMI ID is an explicit root input so plans are reproducible rather than following a moving `latest` parameter. The currently pinned image came from that parameter but has not been validated by launching and testing a Vault node. Review and test a replacement AMI before updating the pin; AMI IDs are region-specific.

Require IMDSv2, disable public IPv4 assignment, and use an encrypted 20 GiB gp3 root volume deleted with the instance. No SSH key or user data is configured. Ansible installation and deterministic Vault bootstrap are separate work; design bootstrap and Raft join behavior before creating an ASG or launching nodes.

## Security and operations

The launch template attaches the existing least-privilege instance profile and Vault-node security group. The profile provides temporary role credentials; it does not create a network path to KMS. No Vault node may receive a public IP. Private-node access will use AWS Systems Manager Session Manager rather than SSH. The instance role will include the managed AWS policy `AmazonSSMManagedInstanceCore`, allowing the SSM agent to register without a public IP. The node still requires the same-AZ NAT route and outbound HTTPS to AWS Systems Manager endpoints. An unhealthy target is expected until Vault is installed and configured.

Replacing a Vault instance is stateful: a replacement must install and configure Vault, use AWS Raft `retry_join` discovery filtered to this cluster, join the existing Raft cluster, and become healthy without initializing an independent cluster. The instance role will need EC2 discovery permissions, and ASG instances need a dedicated discovery tag. Before scaling above zero, verify discovery, TLS peer validation, AZ distribution, and one-node replacement while quorum remains. Never allow automated replacement to initialize an independent cluster.

## Validation

Run `terraform fmt -check`, `terraform validate`, and `terraform plan`. Confirm the launch template retains the pinned AMI, instance profile, private-node security group, IMDSv2, and encrypted root volume. Confirm the ASG spans only private subnets. Validation on 2026-10-08: Terraform changed only ASG desired capacity from zero to one; AWS reports one instance `InService` and ASG healthy in `us-east-1b`. EC2 system and instance status checks were still `initializing` at inspection, and the instance was not registered in Systems Manager. This confirms ASG provisioning only—not guest-level DNS/HTTPS connectivity, Vault behavior, TLS, or NLB target health. The security group permits outbound TCP 443; ICMP ping is not permitted.
