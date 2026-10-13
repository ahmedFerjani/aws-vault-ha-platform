# Architecture

The target is a three-node Vault cluster on EC2 across three availability zones. Vault nodes remain private; clients will use NLB TCP pass-through with TLS terminating at Vault. Raft is the live storage and consensus layer, KMS provides auto-unseal, and encrypted S3 snapshots are the planned backup mechanism. Recovery and node replacement must be handled as stateful operations. These target capabilities are not all implemented or validated yet.

## Core components

- Three EC2 Vault nodes across three AZs
- Private networking for each Vault instance
- AWS NLB for TCP pass-through and client access; TLS terminates at Vault
- Raft integrated storage for cluster coordination
- AWS KMS for auto-unseal
- S3 for encrypted backup snapshots
- Terraform for AWS infrastructure
- Ansible for Vault installation and configuration

## Security model

- Vault nodes remain private and are not publicly routable
- Only the required listener is exposed through the NLB
- IAM permissions are limited to least privilege
- TLS is required for client access
- KMS, Raft, and S3 remain separate responsibilities

## Operational model

- Laptop Ansible uses SSH tunneled through SSM, with IAM session permissions, dedicated SSH keys, and verified host keys; no inbound SSH rule or management EC2 host is required.
- A quorum of 2 keeps the cluster available during a single node failure
- Recovery must respect Raft and quorum rules
- Node replacement must be treated as a stateful operation
- Backup and restore are handled independently from live cluster storage
- The proposed Raft and NLB client-routing design is documented in [raft-ha.md](raft-ha.md); it remains unimplemented pending review and testing.

## Current state

Terraform implements the VPC, three public/private subnet pairs, same-AZ NAT routes, security groups, NLB and target group, KMS key, Vault IAM instance profile, launch template, and ASG. The ASG currently requests one node, not three. It registers instances with the target group, but no NLB listener is implemented. The management module has been removed.

Laptop SSH-over-SSM and Ansible were tested on one private node; the operator reports successful installation and an idempotent repeat. The role's default is to stop and disable Vault, but the current node was manually started for a local hostname-verified TLS/health test and remains disabled at boot. It is still uninitialized/sealed and has no Raft membership. Public NLB/DNS, KMS auto-unseal, first-node initialization, follower joins, three-AZ HA, backup/restore, and failure tests remain pending. KMS/EC2 interface endpoints and S3 backups are not implemented. Confirm live AWS/node state before operating; documented test results are not a guarantee that infrastructure remains running.
