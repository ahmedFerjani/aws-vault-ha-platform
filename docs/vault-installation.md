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

Private-node installation milestone (2026-10-10): the operator reported successful execution of `ansible/site.yml` limited to `vault-node-1` (`i-052c2ed3f740eeaca`) from the laptop using SSH over SSM, followed by a second run with `changed=0` and a check confirming Vault is installed. The full recap and exact installed version output were not supplied. Before deployment, local certificate checks showed SAN `vault.ahmedferjani.com`, validity from 2026-10-05 to 2027-01-03, and matching certificate/private-key public components; playbook syntax check passed. No private-key contents were printed. This validates operator-reported installation and repeated-run idempotency on one private node, not a running Vault service or HA cluster. The role deliberately stops and disables Vault; live service state, installed package version, remote file permissions, rendered HCL, KMS seal access, and TLS handshake should be checked separately before any startup or initialization. Never initialize every node independently.

Historical public-test-host evidence: the role passed `ansible-playbook --syntax-check` and was applied to the disposable `vault-test` host. A second run reported `changed=0`. The rendered HCL points Raft at `/opt/vault/data`, uses the instance private IP for API and cluster addresses, and configures the KMS seal and TLS file paths. The config was `root:vault` mode `0640`; Raft data was `vault:vault` mode `0700`. These file checks have not yet been repeated on the new private node.

## Test inventory setup

The example inventory uses ordinary SSH tunneled through SSM from the laptop. No management host, public node address, or inbound TCP 22 rule is required. This is not the native Ansible SSM connection plugin: SSH keys and host-key verification still apply.

### Prerequisites

- Install Ansible, AWS CLI, and the Session Manager plugin on the laptop. Use short-lived operator credentials where possible.
- Discover a fresh instance ID in `us-east-1` and confirm SSM reports `Online`. The node needs SSM Agent, `sshd`, target SSM permissions, and outbound HTTPS to required SSM endpoints through NAT or VPC endpoints.
- The operator needs narrowly scoped session permissions for the target and `AWS-StartSSHSession`; the node's `AmazonSSMManagedInstanceCore` policy does not grant the operator these permissions.
- Use a dedicated passphrase-protected laptop key. Install only its public half in `ec2-user` authorized_keys through trusted operator SSM access, preserving existing entries. Never transfer a private key onto the node.
- Obtain the ED25519 SSH host public key through that trusted SSM session and store it in laptop known_hosts under the instance ID, not the private IP. Verify new keys after replacement; do not disable host-key checking.
- Keep the certificate chain and matching private key on the laptop outside the repository. Check readability, validity, hostname SANs, and key matching before deployment. These source paths are not remote destinations.
- CloudTrail records session API activity; Session Manager cannot record command contents inside SSH tunnels. Use appropriate host and Vault auditing separately.

### Prepare the local inventory

Run from the project root. This command does not overwrite an existing local inventory:

```bash
cp -n ansible/inventory/test.ini.example ansible/inventory/test.ini
```

Edit the ignored local inventory with the fresh instance ID, absolute laptop SSH-key path, and certificate-chain/private-key source paths. Adjust the proxy region if necessary. Verify the target Python path; `/usr/bin/python3.9` was observed on the current Amazon Linux 2023 node. The example contains placeholders and is not directly deployable. Do not reuse an old public test-host entry. Confirm the local inventory stays ignored:

```bash
git check-ignore ansible/inventory/test.ini
```

Load the SSH key into the laptop agent for a limited period; type its passphrase directly into the terminal:

```bash
ssh-add -t 3600 /absolute/path/to/vault-laptop
```

### Validate access, then deploy one node

```bash
ansible-playbook -i ansible/inventory/test.ini ansible/site.yml --syntax-check
ansible vault-test -i ansible/inventory/test.ini -m ansible.builtin.ping
ansible vault-test -i ansible/inventory/test.ini --become -m ansible.builtin.command -a 'id -u'
```

Expected results: syntax check passes, ping returns `pong`, and become returns UID `0`. The command module reports `CHANGED` by default even though this identity check does not modify the node. Stop on errors rather than disabling host-key verification.

Use only a disposable, non-serving node for this installation stage: the role explicitly stops and disables Vault. Running it against an active cluster could interrupt service and quorum. Install/TLS checks occur after package tasks, so missing certificate files can cause a partial deployment.

```bash
ansible-playbook -i ansible/inventory/test.ini ansible/site.yml --limit vault-test
```

Repeat the same command to test idempotency; expect `changed=0`, `failed=0`, and `unreachable=0`. Record the actual recaps and installed version. Do not start or initialize Vault as part of this procedure. Refresh inventory and trust after any instance replacement; manual public-key authorization is not yet an automated replacement-node design.

Vault remains disabled and inactive. The referenced TLS files exist on the test host, but their SANs, trust chain, and suitability for the final endpoint have not been validated here. Vault has not been started, its HCL has not been runtime-validated, KMS reachability/auto-unseal has not been tested, and no Raft cluster has been initialized. Do not enable or start the service until the TLS lifecycle and safe first-node versus join-node procedure are ready.
