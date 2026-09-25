# Architecture

A three-node Vault cluster runs on EC2 across three availability zones. The cluster is private by default, exposed only through an AWS NLB, and secured with TLS, KMS auto-unseal, and encrypted S3 snapshots. Vault uses Raft for live cluster coordination, so recovery and node replacement must be handled as stateful operations.

## Core components

- Three EC2 Vault nodes across three AZs
- Private networking for each Vault instance
- AWS NLB for TLS termination and client access
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

- A quorum of 2 keeps the cluster available during a single node failure
- Recovery must respect Raft and quorum rules
- Node replacement must be treated as a stateful operation
- Backup and restore are handled independently from live cluster storage

## Current state

The architecture baseline is defined. AWS infrastructure has not been provisioned yet.
