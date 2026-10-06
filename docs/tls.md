# TLS

## Design

Use NLB TCP pass-through on port 443 to Vault's TLS API listener on port 8200. Vault presents a publicly trusted certificate for `vault.ahmedferjani.com`; the client negotiates TLS directly with Vault through the NLB. The NLB does not terminate TLS or inspect decrypted Vault requests.

Use ACME DNS-01 validation through Route 53 for certificate issuance and renewal. The ACME automation must use narrowly scoped DNS permissions and must not place Route 53 credentials on Vault nodes. The resulting certificate and private key must be delivered to each node through a protected channel, stored with restrictive permissions, and never committed to the repository.

For the current test, Ansible copies the production certificate full chain and key from the controller's local Certbot directory to the single disposable `vault-test` host over SSH. The remote files are owned by `root:vault` with mode `0640`, and the TLS directory is `root:vault` mode `0750`. This is a manual test deployment, not the final multi-node renewal/distribution mechanism. The certificate's private key must not be printed, added to inventory, or committed. Vault remains stopped after this step.

## DNS names, peer discovery, and certificate SANs

Use `vault.ahmedferjani.com` as the public client endpoint in the public `ahmedferjani.com` hosted zone; it will be a Route 53 alias to the NLB when the listener is ready. Do not create fixed numbered private DNS names for ASG nodes. Configure Vault Raft AWS `retry_join` discovery filtered by a dedicated cluster tag; each node advertises its current private IPv4 address in `cluster_addr`.

Vault should advertise the public endpoint through `api_addr` so clients redirected by a standby can reach the NLB. The client-facing certificate must include `vault.ahmedferjani.com` in its SAN. Before issuance, validate Raft auto-join TLS peer verification when it discovers private IPs, including `leader_tls_servername` and CA behavior. Do not disable certificate verification to work around SAN or trust errors.

AWS discovery identifies possible peers; it does not preserve Raft identity or membership. A replacement must discover the existing cluster and join it, never initialize an independent cluster. The ASG needs a dedicated discovery tag, and the Vault IAM role needs EC2 discovery permissions required by Vault's AWS provider.

## Operations and risks

- Automate renewal and secure distribution to every Vault node.
- Keep Route 53 DNS-01 credentials off Vault nodes and scope record changes to the required validation names.
- Reload or safely restart Vault after certificate renewal and verify the NLB health check.
- Restrict access to private keys; the Vault service needs read access but not write access to key material.
- Plan for DNS or certificate issuance failure and monitor certificate expiry.
- A public certificate is free from Let's Encrypt, but Route 53 DNS queries/hosted-zone charges and automation operations remain.

## Validation status

Certbot issued a production Let's Encrypt certificate for `vault.ahmedferjani.com`, valid from 2026-10-05 through 2027-01-03. Its SAN contains `DNS:vault.ahmedferjani.com`, and OpenSSL verified its chain against the Mac's trusted CA bundle. The certificate chain and private key were deployed to the disposable `vault-test` host by Ansible. On the host, both files are `root:vault` mode `0640`, certificate metadata matches the expected SAN/issuer/dates, and hashes of the certificate and private-key public keys match. A repeated Ansible run reported `changed=0`. Manual DNS validation was used, so renewal is not automated; the temporary `_acme-challenge.vault.ahmedferjani.com` TXT record was removed after issuance.

The older test-host certificate was self-signed (`O=HashiCorp, CN=Vault`), valid from 2026-10-03 through 2029-10-02, and had no SAN; it was not suitable for the public hostname and has been replaced in the configured TLS paths. Vault remains disabled and inactive. The NLB has no listener, and no client TLS handshake has been tested. The public Route 53 alias and AWS Raft auto-join/TLS peer validation are pending. Complete these checks before enabling the Vault service or public listener.
