# aws-vault-ha-platform

HashiCorp Vault on AWS infrastructure project, built in validated stages toward high availability and stateful recovery.

## Scope

- Target: three Vault nodes across three availability zones
- Private-only networking for Vault instances
- End-to-end client TLS through NLB TCP pass-through to Vault
- Raft integrated storage for cluster coordination
- AWS KMS for auto-unseal
- Planned S3 encrypted snapshots
- Terraform for AWS infrastructure
- Ansible for Vault installation and configuration

## Project docs

- Architecture: [docs/architecture.md](docs/architecture.md)
- Decisions: [docs/decisions.md](docs/decisions.md)
- Raft HA and recovery: [docs/raft-ha.md](docs/raft-ha.md)
- Terraform: [terraform/README.md](terraform/README.md)
- Installation and laptop SSH-over-SSM instructions: [docs/vault-installation.md](docs/vault-installation.md)

## Current state

The current development deployment is **one private Vault node**. The operator reports that Vault was initialized, the recovery bundle was stored, Vault remained unsealed after a controlled restart, and the single-node NLB/DNS endpoint was configured and health-tested. This is not three-node HA. Raft follower joins, quorum/failover tests, automated replacement, S3 snapshots, and restore-tested disaster recovery remain incomplete. Confirm live AWS and service state before operating. See [installation and node-access](docs/vault-installation.md) and [compute operations](docs/compute.md).
