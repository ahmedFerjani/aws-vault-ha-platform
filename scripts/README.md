# Scripts

Scripts are grouped by responsibility:

- `access/` — prepare laptop SSH-over-SSM access with SSM Run Command; includes a manual node-authorization fallback.
- `deployment/` — check Ansible connectivity and deploy the Vault role to one node.
- `vault-bootstrap/` — preflight/store the one-time Vault initialization bundle, its tests, and the `boto3` requirement.

Run the helper commands from the repository root as shown in `docs/vault-installation.md` and `docs/raft-ha.md`.
