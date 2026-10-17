# Scripts

Scripts are grouped by responsibility:

- `access/` — prepare laptop SSH-over-SSM access and authorize its public key on a node.
- `deployment/` — check Ansible connectivity and deploy the Vault role to one node.
- `vault-bootstrap/` — preflight/store the one-time Vault initialization bundle, its tests, and the `boto3` requirement.

Run the helper commands from the repository root as shown in `docs/vault-installation.md` and `docs/raft-ha.md`.
