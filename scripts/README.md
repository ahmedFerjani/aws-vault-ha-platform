# Scripts

Scripts are grouped by responsibility:

- `access/` — helper used by `ansible/access-vault-node.yml` to prepare SSH-over-SSM; includes a manual node-authorization fallback.
- `vault-bootstrap/` — preflight/store the one-time Vault initialization bundle, its tests, and the `boto3` requirement.

Connectivity checks and Vault deployment are native Ansible tasks in `ansible/deploy-vault-node.yml`. Run the Ansible playbooks from the repository root as documented in `docs/vault-installation.md`; helper scripts are invoked by those playbooks. The manual node-authorization script is a fallback only.
