# Vault installation and node access

## Current design

Terraform launches Vault EC2 instances in private subnets. The laptop is the Ansible controller. SSH is tunneled to each instance through Systems Manager `AWS-StartSSHSession`; this is ordinary SSH over SSM, not Ansible's native SSM connection plugin. No management EC2 host, public node IP, or inbound TCP 22 rule is required.

The access layers are separate:

1. IAM authorizes the operator to start an SSM session; SSM carries the network tunnel.
2. The laptop's private SSH key authenticates `ec2-user`. Only its public key is installed on the node.
3. The node's SSH host public key is verified and pinned in laptop `known_hosts` under the EC2 instance ID.

Session Manager does not record SSH command contents inside the tunnel. CloudTrail can record session API activity; use host and Vault audit controls for command/API auditing. Never disable SSH host-key checking or TLS verification to work around trust errors.

## Prerequisites

- Laptop: Bash, AWS CLI, Session Manager plugin, OpenSSH tools, Ansible, and access to the TLS certificate chain and matching private key.
- AWS: operator credentials with narrowly scoped `ssm:StartSession` access to the target and `AWS-StartSSHSession` document.
- Node: EC2 running, SSM Agent online, `sshd` active, `AmazonSSMManagedInstanceCore` attached, and outbound HTTPS to required AWS/package endpoints.
- Local inventory: fresh EC2 instance ID, region, remote Python path, laptop SSH-key path, and laptop-local TLS source paths.

The node's SSM policy permits registration; it does not grant the operator permission to start sessions. Keep the SSH private key and TLS private key on the laptop, outside Git.

## Prepare an ignored local inventory

Run from the project root. This does not overwrite an existing local inventory:

```bash
cp -n ansible/inventory/test.ini.example ansible/inventory/test.ini
```

Set the fresh instance ID, region in the SSH proxy, laptop SSH-key path, target Python path, and absolute laptop paths to the TLS files. Confirm the local file is ignored:

```bash
git check-ignore ansible/inventory/test.ini
```

## Prepare SSH-over-SSM for a recreated instance

Run the laptop helper in terminal 1:

```bash
bash scripts/prepare-ssm-ssh-laptop.sh i-REPLACE_WITH_INSTANCE_ID us-east-1
```

It verifies EC2 is running and SSM Online, reuses `~/.ssh/vault-laptop` or creates an Ed25519 key if neither half exists, prints the laptop public key, and waits for the node host public key. It refuses to overwrite an existing private key. Leave this terminal open.

In terminal 2, open an interactive SSM shell to the same instance:

```bash
aws ssm start-session --region us-east-1 --target i-REPLACE_WITH_INSTANCE_ID
```

In that SSM shell, stage the node helper by running:

```bash
sudo tee /tmp/authorize-ssm-ssh-node.sh >/dev/null
```

Paste the complete contents of `scripts/authorize-ssm-ssh-node.sh` from the laptop editor and press Ctrl-D. Run it:

```bash
sudo bash /tmp/authorize-ssm-ssh-node.sh
```

Paste the laptop public key printed by the waiting laptop helper. The node helper validates and appends that key once to `ec2-user`'s `authorized_keys` with OpenSSH `restrict`, preserves other keys, and prints the node's ED25519 host public key. Copy the complete host-key line from this trusted SSM session. Remove the temporary helper:

```bash
sudo rm -f /tmp/authorize-ssm-ssh-node.sh
```

Return to terminal 1 and paste the node host public key. The laptop helper fingerprints it and pins it under the instance ID. If a different fingerprint is already recorded, it stops; investigate rather than replacing trust.

## Check Ansible connectivity

Load the laptop key into the SSH agent for a limited time:

```bash
ssh-add -t 3600 ~/.ssh/vault-laptop
```

Run the check-only preflight:

```bash
bash scripts/check-ansible-connectivity.sh
```

With no arguments, it uses `ansible/inventory/private.ini` and `vault-node-1`. Override these with `INVENTORY HOST_ALIAS` arguments. The helper forces host-key checking, tests SSH/remote Python with Ansible ping, then tests `become` with read-only `id -u`. Expect `pong` and UID `0`. It exits nonzero on failure and never runs the playbook. The command module may label `id -u` `CHANGED` by default; the command itself does not alter the node.

## Deploy Vault to one node

Review the local inventory and verify that both TLS source files exist, are readable, valid for `vault.ahmedferjani.com`, and match. Check playbook syntax:

```bash
ansible-playbook -i ansible/inventory/private.ini ansible/site.yml --syntax-check
```

Run the deployment helper:

```bash
bash scripts/deploy-vault-node.sh
```

With no arguments, it uses `ansible/inventory/private.ini` and `vault-node-1`; override with `INVENTORY HOST_ALIAS`. It verifies that exactly one host is selected, runs syntax and connectivity checks, then requires typing `DEPLOY-vault-node-1` before deploying to that host only. Review the inventory target and TLS source paths before confirming.

**The Ansible role stops and disables `vault.service`.** Run it only on a disposable, non-serving node; applying it to a serving cluster can interrupt service and quorum. Missing TLS files can cause partial installation because package tasks precede TLS checks. Run the helper again to test idempotency; a converged node should report `changed=0`, `failed=0`, and `unreachable=0`. Installation does not start or initialize Vault.

## Current checkpoint and next Raft step

The operator reports successful use of the SSH setup, connectivity, and deployment scripts after infrastructure recreation. The node is configured for Vault 2.1.1; the role leaves Vault stopped/disabled. Confirm current AWS, service, and Raft state before operating; instance IDs and host keys change on recreation.

Before first-node initialization, inspect the current rendered HCL and verify the intended API address, private `cluster_addr`, TLS peer identity/trust, KMS key access, and initialization-output handling. Initialization is a one-time, stateful action; future nodes must join the existing Raft cluster, never initialize separate clusters. Three-node HA, auto-unseal, public NLB service, and Raft joins are not yet validated.
