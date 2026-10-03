# Vault installation

## Design

The `vault` Ansible role configures HashiCorp's official Amazon Linux RPM repository and installs the exact `vault-2.1.1-1` package on Amazon Linux 2023 x86_64. The repository uses `gpgcheck=1`, and DNF verifies RPM package signatures using the configured HashiCorp key. The role does not pin a key fingerprint; verify HashiCorp's current RPM signing key through a trusted source before production use.

The repository URL uses HashiCorp's `AmazonLinux/latest/$basearch/stable` channel. `latest` here identifies the supported Amazon Linux repository path; it does not select the Vault package version. The role pins both the Vault version (`2.1.1`) and RPM release (`1`). Package installation relies on RPM signature verification rather than the separate ZIP SHA-256 variable. Vault nodes need outbound HTTPS access to the repository, or a trusted internal mirror, before this role can install the package.

The role ensures a dedicated non-login `vault` user and group, `/etc/vault.d` for configuration, and `/opt/vault/data` for local Raft data. The RPM provides the Vault package and platform service files; Ansible enforces the intended account and directory ownership afterward. Configuration files are root-owned and readable by the `vault` group; the Raft data directory is owned by `vault:vault` with mode `0700`, so only the Vault service user can access its contents. TLS material, service enablement/start policy, initialization, and Raft join remain separate steps. Installing Vault must never initialize a cluster.

## Security and operations

- Pin the package version and RPM release in role defaults; review both together when upgrading.
- Keep GPG package verification enabled; verify the HashiCorp RPM signing key through a trusted source before production use.
- Keep Vault configuration root-owned and readable by the service group; keep Raft data writable by the `vault` service user.
- Do not place tokens, unseal material, or private TLS keys in Ansible variables committed to the repository.
- A replacement node must discover the existing cluster and join it; it must not initialize an independent cluster.

## Validation

Run `ansible-playbook --syntax-check` against the role's site playbook. Idempotence requires running the role twice against a reachable test host and confirming the second run reports no changes. This initial installation step does not validate Vault configuration, auto-unseal, or Raft behavior.
