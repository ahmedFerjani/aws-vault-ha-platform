# aws-vault-ha-platform

Production-oriented HashiCorp Vault on AWS lab focused on high availability, stateful recovery, and operational realism.

## Scope

- Three Vault nodes across three availability zones
- Private-only networking for Vault instances
- End-to-end client TLS through NLB TCP pass-through to Vault
- Raft integrated storage for cluster coordination
- AWS KMS for auto-unseal
- S3 for encrypted snapshots
- Terraform for AWS infrastructure
- Ansible for Vault installation and configuration

## Project docs

- Architecture: [docs/architecture.md](docs/architecture.md)
- Decisions: [docs/decisions.md](docs/decisions.md)
- Terraform: [terraform/README.md](terraform/README.md)
- Installation and laptop SSH-over-SSM instructions: [docs/vault-installation.md](docs/vault-installation.md)

## Current state

The current development iteration uses one private Vault node. The operator reports the laptop SSH-over-SSM setup and Ansible workflow succeeded, including an idempotent repeat. The installation role deliberately leaves Vault stopped and disabled. Confirm current AWS/service state before operating; three-node Raft HA, first-node initialization, KMS auto-unseal, an active NLB endpoint, replacement, and disaster recovery remain unvalidated. See [the installation and node-access procedure](docs/vault-installation.md) for the current flow and [compute operations](docs/compute.md) for stateful-node safety.
