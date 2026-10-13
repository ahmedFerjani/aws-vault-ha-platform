# Compute and node operations

## Terraform implementation

Terraform provisions an EC2 launch template and Auto Scaling Group spanning three private subnets. The current ASG settings are minimum 0, desired 1, maximum 3: this is a single-node development iteration, not a three-node HA cluster. The ASG registers instances with the NLB target group, but an NLB listener is not implemented.

The launch template uses the pinned Amazon Linux 2023 x86_64 AMI, `t3.medium`, the Vault instance profile and security group, IMDSv2, no public IPv4 address, and an encrypted 20 GiB gp3 root volume deleted on instance termination. No EC2 key pair or user data is configured.

Terraform owns AWS resources. Ansible installs Vault, creates the service identity and directories, distributes TLS, and renders configuration. The role deliberately stops and disables Vault. Installation alone does not make a healthy Vault target.

## Administrative access

The laptop runs Ansible using SSH tunneled over SSM. The node stays private; no management EC2 host, public node address, or inbound SSH rule is required. IAM authorizes tunnel access, an SSH key authenticates `ec2-user`, and a separately verified host key protects server identity. Session Manager does not capture SSH command contents.

The repeatable manual setup, preflight, and deployment flow is documented in [vault-installation.md](vault-installation.md). Re-run setup after manual infrastructure recreation. Automated ASG replacement access is a separate, not-yet-designed capability.

## Stateful operation and safety

Vault is stateful. A three-node Raft cluster needs two nodes for quorum; losing two removes quorum. Treat ASG as possible infrastructure replacement, not permission for uncontrolled scale-in/out. A future replacement workflow must install/configure a node, discover the existing cluster, verify TLS, join Raft, and become healthy without initializing another cluster.

Before terminating or scaling down initialized nodes, review Raft membership, quorum, snapshots, and recovery. Root EBS is deleted at termination. Preserve required data with a tested snapshot/restore procedure and preserve the original KMS key; recreating an alias does not recreate the cryptographic key. The KMS key has `prevent_destroy` and a 30-day deletion window. Review recurring NAT, EIP, NLB, and volume costs before teardown.

## Current checkpoint

The operator reports successful use of the laptop SSH-over-SSM and Ansible scripts after infrastructure recreation. One node is configured for Vault 2.1.1, and the role leaves the service stopped and disabled. Confirm current AWS, service, and Raft state before continuing. Three-node Raft, initialization/join, KMS auto-unseal, NLB serving traffic, automated replacement, failure recovery, and backup restore remain unvalidated.
