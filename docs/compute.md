# Compute

## Design and implementation

Terraform uses an EC2 launch template and an ASG spanning the three private subnets. Current capacity is minimum 0, desired 1, maximum 3 for the single-node installation iteration. This is not a three-node HA deployment. The ASG uses EC2 health checks and registers instances with the NLB target group; the NLB listener is not implemented.

The launch template uses the explicitly pinned Amazon Linux 2023 x86_64 AMI and `t3.medium` root inputs, the Vault instance profile, and the Vault security group. It requires IMDSv2, disables public IP assignment, and provides an encrypted 20 GiB gp3 root volume deleted on termination. No EC2 key pair or user data is configured. Ansible installation was tested on a manually accessed private instance; safe unattended replacement bootstrap remains future work. Verify any replacement AMI before changing the pin.

Terraform creates the instance; Ansible installs Vault, its account, directories, TLS material, and configuration. The installation role deliberately stops and disables Vault. Installed software is not proof of a functioning NLB target or a healthy Raft member.

## Administrative access: laptop SSH over SSM

The controller is the operator's laptop. Ordinary SSH is tunneled through `AWS-StartSSHSession` using fresh instance IDs. No management EC2 host, public node IP, direct private-IP route from the laptop, or inbound TCP 22 rule is required.

- The controller needs AWS CLI, the Session Manager plugin, Ansible, and IAM permission to initiate the permitted sessions.
- Nodes have `AmazonSSMManagedInstanceCore`, SSM Agent, and outbound HTTPS through NAT. This target policy is not controller permission to start sessions.
- SSH authentication still requires an authorized key. Provision only the laptop public key through trusted operator SSM access, and keep the private key outside the repository.
- Verify the node's ED25519 host public key through the trusted SSM channel and index it by instance ID in laptop known_hosts. Retain strict host-key checking.
- CloudTrail can record session API activity; Session Manager cannot record SSH command contents. Host auditing and Vault auditing are separate controls.

Use [vault-installation.md](vault-installation.md) and [the example inventory](../ansible/inventory/test.ini.example) for setup and testing. Manual public-key authorization is not yet a replacement-node solution. CI controller placement will be designed in the CI/CD iteration.

## Security, failure, and replacement

Vault nodes remain private. Their dedicated role supplies temporary credentials and key-scoped KMS usage permissions; their network path to AWS APIs currently uses NAT-backed HTTPS. SSM registration and package installation have been exercised on one node, but actual Vault KMS seal operations have not.

The ASG is intended for infrastructure replacement, not uncontrolled Vault scaling. A future replacement must receive configuration and TLS, discover the existing cluster, join Raft, and become healthy without initializing a separate cluster. AWS discovery permissions, a dedicated discovery tag, and `retry_join` are still pending. Before expanding to a serving cluster, design initialization/join and validate peer TLS, AZ distribution, and one-at-a-time replacement. Three Raft nodes need two for quorum.

Do not scale down, terminate, or destroy initialized nodes merely to stop costs without reviewing state and recovery consequences. Root EBS volumes are deleted on termination. Preserve required data with a verified backup procedure and retain the original auto-unseal KMS key: recreating an alias does not recreate its cryptographic material. The KMS resource currently has `prevent_destroy` and a 30-day deletion window. Do not bypass that safeguard blindly. Review residual NAT, NLB, EIP, volume, and retained-resource costs after any approved teardown.

## Current validation evidence (2026-10-10)

- AWS reported `i-052c2ed3f740eeaca` SSM Online with Agent 3.3.5226.0.
- Operator-supplied strict-host-key SSH-over-SSM output returned `ip-10-16-1-250.ec2.internal`, UID 1000 (`ec2-user`), and Python 3.9.25.
- The operator reported successful Ansible ping and become over the laptop tunnel, then successful playbook deployment and a repeat run with `changed=0`. Full recaps and exact installed version output were not supplied. See [installation evidence](vault-installation.md#validation).
- The private inventory pins the observed `/usr/bin/python3.9` interpreter. Refresh instance IDs and host trust after replacement.
- Removing the unused management module, commented invocation, and nine root inputs found no management resources in Terraform state. Formatting and validation passed; the live plan reported no changes. No apply was performed for that cleanup.

These are recorded results, not proof the environment is currently running. Live Vault service state, remote file permissions, HCL runtime validity, TLS handshake, KMS auto-unseal, Raft membership, multi-AZ HA, and automated replacement remain unvalidated. Next: read-only installation checks, then deliberate TLS/runtime and first-node/join design before startup.

## Historical evidence: management-host approach (superseded)

The earlier management-host experiment used direct SSH to a private smoke-test node at `10.16.1.63`. Operator output confirmed TCP SSH reachability, authenticated SSH as `ec2-user`, Python 3.9.25, Ansible `ping: pong`, and become output UID 0. The identity command's `CHANGED` label was normal command-module reporting, not a host modification.

An explicitly approved management replacement applied with `1 added, 1 changed, 1 destroyed`, creating `i-01863adcb384f02c7` and adding scoped direct SSH egress. The Vault node was not part of those changes. This is historical evidence, not a resource or configuration to recreate.

Bootstrap lessons from that removed module:

- Requesting the full `curl` RPM conflicted with Amazon Linux's installed `curl-minimal`, aborting the package transaction. Retain the existing curl implementation instead of masking the conflict with `--allowerasing` or `--skip-broken`.
- Upgrading RPM-owned pip failed because it lacked a pip `RECORD` file. Manual repair used an isolated Python 3.11 Ansible virtual environment, preserving system package ownership. An unattended bootstrap of the correction was not validated before the module was removed.
- User-data replacement can erase controller-local files and keys. Inspect and explicitly approve destructive plans; do not assume a working controller is disposable.

The obsolete management-host setup and pause/rebuild procedures are no longer operational instructions. Follow the laptop SSH-over-SSM procedure above instead.
