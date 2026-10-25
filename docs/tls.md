# TLS

## Design

The Network Load Balancer uses TCP pass-through on port 443 to Vault's TLS listener on port 8200. Vault terminates TLS and presents a publicly trusted certificate for `vault.ahmedferjani.com`; the NLB does not decrypt API traffic.

Issue and renew the certificate using ACME DNS-01 with narrowly scoped Route 53 permissions. Do not put DNS credentials on Vault nodes. Distribute the full certificate chain and matching private key through Ansible from the laptop controller. Keep the key outside the repository and restrict its source permissions. On the node, the Ansible role sets the certificate and key to `root:vault 0640` and the TLS directory to `root:vault 0750`.

The client-facing certificate must include `vault.ahmedferjani.com` in its SAN. Vault's `api_addr` advertises the stable NLB hostname; each node's `cluster_addr` advertises its private address for Raft traffic. The Ansible template uses those distinct addresses. The operator reports a hostname-validated HTTPS health request through the NLB succeeded for the single-node deployment.

Raft `retry_join` via AWS discovery is configured in the Vault template, but has not been tested by joining a follower. Discovered private peers validate TLS using SNI/`leader_tls_servername`, the certificate SAN, and the configured CA trust. Never disable verification to work around a mismatch. AWS discovery must filter to this cluster, and replacement nodes must join existing Raft state rather than initialize a separate cluster.

## Operations and security

- Renew certificates before expiry and distribute them to every Vault node through a protected, repeatable process.
- Keep Route 53 DNS-01 permissions scoped to required validation records; keep credentials off Vault nodes.
- After renewal, apply a safe reload/restart procedure and verify the certificate and NLB target health.
- Monitor certificate expiry and plan for DNS/ACME failure.
- Never print private-key contents, store them in inventory, or commit them.

## Current validation status

The operator reports hostname-validated local TLS and an HTTPS health request through the NLB succeeded on the single node. Automated certificate renewal, Raft peer TLS validation, standby redirects, and multi-node routing remain untested. Always use normal certificate verification; never use insecure TLS flags.
