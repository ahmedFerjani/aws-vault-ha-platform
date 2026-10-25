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
- The Raft/NLB design and remaining HA validation are documented in [raft-ha.md](raft-ha.md).

## Current state

Terraform provisions the network, NLB listener/target group, DNS alias, separate auto-unseal and recovery KMS keys, recovery secret/bootstrap role, and Vault compute/IAM. The ASG desired capacity is one. The operator reports a working initialized single-node endpoint; this is not HA. See [raft-ha.md](raft-ha.md) for the latest validation details and remaining cluster work. Confirm live AWS/node state before operating.
