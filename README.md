# aws-vault-ha-platform

Production-oriented HashiCorp Vault on AWS lab focused on high availability, stateful recovery, and operational realism.

## Scope

- Three Vault nodes across three availability zones
- Private-only networking for Vault instances
- TLS termination at the AWS Network Load Balancer
- Raft integrated storage for cluster coordination
- AWS KMS for auto-unseal
- S3 for encrypted snapshots
- Terraform for AWS infrastructure
- Ansible for Vault installation and configuration

## Project docs

- Architecture: [docs/architecture.md](docs/architecture.md)
- Decisions: [docs/decisions.md](docs/decisions.md)
- Terraform: [terraform/README.md](terraform/README.md)

## Current state

Architecture baseline only. AWS infrastructure has not been provisioned yet.
