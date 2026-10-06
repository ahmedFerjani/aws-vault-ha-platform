# Vault installation

## Design

The `vault` Ansible role configures HashiCorp's official Amazon Linux RPM repository and installs the exact `vault-2.1.1-1` package on Amazon Linux 2023 x86_64. The repository uses `gpgcheck=1`, and DNF verifies RPM package signatures using the configured HashiCorp key. The role does not pin a key fingerprint; verify HashiCorp's current RPM signing key through a trusted source before production use.

The repository URL uses HashiCorp's `AmazonLinux/latest/$basearch/stable` channel. `latest` here identifies the supported Amazon Linux repository path; it does not select the Vault package version. The role pins both the Vault version (`2.1.1`) and RPM release (`1`). Package installation relies on RPM signature verification rather than the separate ZIP SHA-256 variable. Vault nodes need outbound HTTPS access to the repository, or a trusted internal mirror, before this role can install the package.

The role ensures a dedicated non-login `vault` user and group, `/etc/vault.d` for configuration, and `/opt/vault/data` for local Raft data. The RPM provides the Vault package and platform service files; Ansible enforces the intended account and directory ownership afterward. Configuration files are root-owned and readable by the `vault` group; the Raft data directory is owned by `vault:vault` with mode `0700`, so only the Vault service user can access its contents. TLS material, service enablement/start policy, initialization, and Raft join remain separate steps. Installing Vault must never initialize a cluster.

The managed server configuration uses Raft at `/opt/vault/data`, AWS KMS auto-unseal, a TLS-enabled API listener on 8200, and the node's private address for `api_addr` and `cluster_addr`. TLS certificate files are expected under `/opt/vault/tls`; their secure creation and distribution belong to the TLS stage. The role writes `/etc/vault.d/vault.hcl` as `root:vault` mode `0640` and explicitly keeps `vault.service` stopped and disabled. Enabling it would start Vault automatically on a future boot, so wait until certificates and safe cluster initialization/join behavior are validated. Cluster initialization and peer joining are separate, stateful operations.

## Security and operations

- Pin the package version and RPM release in role defaults; review both together when upgrading.
- Keep GPG package verification enabled; verify the HashiCorp RPM signing key through a trusted source before production use.
- Keep Vault configuration root-owned and readable by the service group; keep Raft data writable by the `vault` service user.
- Do not start Vault until TLS files and the safe first-node versus join-node procedure are ready.
- Do not place tokens, unseal material, or private TLS keys in Ansible variables committed to the repository.
- A replacement node must discover the existing cluster and join it; it must not initialize an independent cluster.

## Validation

The role passed `ansible-playbook --syntax-check` and was applied to the disposable `vault-test` host. A second run reported `changed=0`. The rendered HCL points Raft at `/opt/vault/data`, uses the instance private IP for API and cluster addresses, and configures the KMS seal and TLS file paths. The config is `root:vault` mode `0640`; Raft data is `vault:vault` mode `0700`.

## Test inventory setup

The repository includes `ansible/inventory/test.ini.example` as a template. For a local test, copy it to the ignored `ansible/inventory/test.ini`, then replace the placeholders with the test EC2 public DNS name, the absolute path to your SSH private key, and the local Certbot `fullchain.pem` and `privkey.pem` paths. The certificate and private key must remain local and must never be committed. Run the playbook with `ansible-playbook -i ansible/inventory/test.ini ansible/site.yml --limit vault-test`.

Vault remains disabled and inactive. The referenced TLS files exist on the test host, but their SANs, trust chain, and suitability for the final endpoint have not been validated here. Vault has not been started, its HCL has not been runtime-validated, KMS reachability/auto-unseal has not been tested, and no Raft cluster has been initialized. Do not enable or start the service until the TLS lifecycle and safe first-node versus join-node procedure are ready.
