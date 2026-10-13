# TLS

## Design

The Network Load Balancer is intended to use TCP pass-through on port 443 to Vault's TLS listener on port 8200. Vault terminates TLS and presents a publicly trusted certificate for `vault.ahmedferjani.com`; the NLB does not decrypt API traffic.

Issue and renew the certificate using ACME DNS-01 with narrowly scoped Route 53 permissions. Do not put DNS credentials on Vault nodes. Distribute the full certificate chain and matching private key through Ansible from the laptop controller. Keep the key outside the repository and restrict its source permissions. On the node, the Ansible role sets the certificate and key to `root:vault 0640` and the TLS directory to `root:vault 0750`.

The client-facing certificate must include `vault.ahmedferjani.com` in its SAN. Vault's public `api_addr` should advertise the stable NLB hostname so clients redirected from a standby can reach the cluster. Each node's `cluster_addr` must advertise its private address for Raft traffic. The current template uses the private address for both API and cluster URLs; correct and validate the API address before exposing a listener.

Raft `retry_join` via AWS discovery is not yet implemented. Before enabling it, design how discovered private peers validate TLS, including SNI/`leader_tls_servername`, certificate SANs, and CA trust. Never disable verification to work around a mismatch. AWS discovery must filter to this cluster, and replacement nodes must join existing Raft state rather than initialize a separate cluster.

## Operations and security

- Renew certificates before expiry and distribute them to every Vault node through a protected, repeatable process.
- Keep Route 53 DNS-01 permissions scoped to required validation records; keep credentials off Vault nodes.
- After renewal, apply a safe reload/restart procedure and verify the certificate and NLB target health.
- Monitor certificate expiry and plan for DNS/ACME failure.
- Never print private-key contents, store them in inventory, or commit them.

## Current validation status

The operator has a Let's Encrypt certificate chain for `vault.ahmedferjani.com`; local checks confirmed the SAN, certificate validity at the time of deployment, and that the certificate matches its private key. Ansible successfully copied TLS files to a private node as part of the reported installation. The operator reports the Ansible repeat was idempotent. Verify the current node's TLS file permissions and perform a hostname-validated TLS handshake before service startup.

No automated certificate renewal/distribution, NLB listener, public DNS alias, Vault API redirect validation, or Raft peer TLS validation is complete. Vault TLS is not considered production-ready until those flows are implemented and tested with normal certificate verification.
