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

AWS infrastructure has been provisioned for a single-private-node smoke test. Laptop SSH-over-SSM access was validated; the operator reported successful Vault installation through Ansible and a second run with `changed=0`. The unused management-host module has been removed; administrative configuration uses laptop SSH over SSM. These are historical validation results, not a guarantee that the lab is currently running. Three-node Raft HA, live TLS, KMS auto-unseal, replacement, and disaster recovery remain unvalidated. Vault is deliberately kept stopped and disabled by the installation role.
