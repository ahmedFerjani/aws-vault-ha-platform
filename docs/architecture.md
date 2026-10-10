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

## Current state

Terraform implements the VPC, three public/private subnet pairs, same-AZ NAT routes, security groups, NLB and target group, KMS key, Vault IAM instance profile, launch template, and ASG. The ASG currently requests one node, not three. It registers instances with the target group, but no NLB listener is implemented. The management module has been removed.

Laptop SSH-over-SSM was tested on a private node. The operator reported successful Ansible ping, become, Vault installation, and a second playbook run with `changed=0`. The role keeps Vault stopped and disabled. Live TLS, KMS auto-unseal, Raft initialization/join, three-AZ HA, backup/restore, and failure tests remain pending. Route 53 alias records, KMS/EC2 interface endpoints, and S3 backups are not implemented. These are recorded milestones, not a guarantee that the lab is currently running.
