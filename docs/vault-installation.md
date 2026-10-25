# Vault installation and node access

## Current design

Terraform launches Vault EC2 instances in private subnets. The laptop is the Ansible controller. SSH is tunneled to each instance through Systems Manager `AWS-StartSSHSession`; this is ordinary SSH over SSM, not Ansible's native SSM connection plugin. No management EC2 host, public node IP, or inbound TCP 22 rule is required.

The access layers are separate:

1. IAM authorizes the operator to start an SSM session; SSM carries the network tunnel.
2. The laptop's private SSH key authenticates `ec2-user`. Only its public key is installed on the node.
3. The node's SSH host public key is verified and pinned in laptop `known_hosts` under the EC2 instance ID.

Session Manager does not record SSH command contents inside the tunnel. CloudTrail can record session API activity; use host and Vault audit controls for command/API auditing. Never disable SSH host-key checking or TLS verification to work around trust errors.

## Workflow at a glance

For a newly created or recreated node, follow this order: (1) review and apply the Terraform plan; (2) update the ignored `ansible/inventory/private.ini` with the new instance ID; (3) use the two `scripts/access/` helpers to authorize laptop SSH and pin the node host key through SSM; (4) run the connectivity check and, if Vault needs installation, the deployment helper; (5) prepare the controller and run the one-time bootstrap playbook. Do not run the deployment helper against an initialized or serving node: it stops and disables Vault.

## Prerequisites

- Laptop: Bash, AWS CLI, Session Manager plugin, OpenSSH tools, Ansible, and access to the TLS certificate chain and matching private key.
- AWS: operator credentials with narrowly scoped `ssm:StartSession` access to the target and `AWS-StartSSHSession` document.
- Node: EC2 running, SSM Agent online, `sshd` active, `AmazonSSMManagedInstanceCore` attached, and outbound HTTPS to required AWS/package endpoints.
- Local inventory: fresh EC2 instance ID, region, remote Python path, laptop SSH-key path, and laptop-local TLS source paths.

The node's SSM policy permits registration; it does not grant the operator permission to start sessions. Keep the SSH private key and TLS private key on the laptop, outside Git.

## Configure the ignored working inventory

Use `ansible/inventory/private.ini` as the working inventory. If it does not exist, create it from the example without overwriting an existing file:

```bash
cp -n ansible/inventory/test.ini.example ansible/inventory/private.ini
```

Set the current instance ID, SSM region, laptop SSH-key path, remote Python path, and absolute laptop TLS source paths. Confirm the local file is ignored:

```bash
git check-ignore ansible/inventory/private.ini
```

## Prepare SSH-over-SSM for a recreated instance

Use both helpers in `scripts/access/`; no inbound SSH rule is required. The laptop helper checks instance/SSM readiness and handles the laptop key and host-key pinning. The node helper, run in the trusted SSM shell, installs only the laptop's public key.

Run the laptop helper in terminal 1:

```bash
bash scripts/access/prepare-ssm-ssh-laptop.sh i-REPLACE_WITH_INSTANCE_ID us-east-1
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

Paste the complete contents of `scripts/access/authorize-ssm-ssh-node.sh` from the laptop editor and press Ctrl-D. Run it:

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
bash scripts/deployment/check-ansible-connectivity.sh
```

With no arguments, it uses `ansible/inventory/private.ini` and `vault-node-1`. Override these with `INVENTORY HOST_ALIAS` arguments. The helper forces host-key checking, tests SSH/remote Python with Ansible ping, then tests `become` with read-only `id -u`. Expect `pong` and UID `0`. It exits nonzero on failure and never runs the playbook. The command module may label `id -u` `CHANGED` by default; the command itself does not alter the node.

## Deploy Vault to one node

Review the local inventory and verify that both TLS source files exist, are readable, valid for `vault.ahmedferjani.com`, and match. Check playbook syntax:

```bash
ansible-playbook -i ansible/inventory/private.ini ansible/site.yml --syntax-check
```

Run the deployment helper:

```bash
bash scripts/deployment/deploy-vault-node.sh
```

With no arguments, it uses `ansible/inventory/private.ini` and `vault-node-1`; override with `INVENTORY HOST_ALIAS`. It verifies that exactly one host is selected, runs syntax and connectivity checks, then requires typing `DEPLOY VAULT NODE 1` before deploying to that host only. The phrase is derived from the selected inventory alias. Review the inventory target and TLS source paths before confirming.

**The Ansible role stops and disables `vault.service`.** Run it only on a disposable, non-serving node; applying it to a serving cluster can interrupt service and quorum. Missing TLS files can cause partial installation because package tasks precede TLS checks. Run the helper again to test idempotency; a converged node should report `changed=0`, `failed=0`, and `unreachable=0`. Installation does not start or initialize Vault.

## One-time Vault initialization and recovery storage

This is a manual, one-time operation. Terraform must already have created the Vault node, recovery KMS key, empty Secrets Manager secret, and bootstrap role. Do not run Terraform apply as part of this procedure without reviewing a new plan and its costs.

### 1. Prepare the controller

Run from the repository root. Activate the project environment and install the helper dependency:

```bash
source .venv/bin/activate
python -m pip install -r scripts/vault-bootstrap/requirements.txt
```

Set the AWS region and get the non-secret identifiers from Terraform outputs. If using a named AWS profile, export `AWS_PROFILE` before continuing. The source AWS identity must be allowed to assume the bootstrap role.

```bash
export AWS_REGION=us-east-1
export VAULT_BOOTSTRAP_PYTHON="$PWD/.venv/bin/python"
export VAULT_BOOTSTRAP_ROLE_ARN="$(terraform -chdir=terraform output -raw vault_bootstrap_role_arn)"
export VAULT_RECOVERY_SECRET_NAME="$(terraform -chdir=terraform output -raw vault_recovery_secret_name)"
export VAULT_RECOVERY_KMS_KEY_ARN="$(terraform -chdir=terraform output -raw vault_recovery_kms_key_arn)"
```

### 2. Check the node and playbook

Ensure `ansible/inventory/private.ini` points to the current `vault-node-1` instance and that verified SSH-over-SSM access is ready. For a new/recreated instance, follow [Prepare SSH-over-SSM for a recreated instance](#prepare-ssh-over-ssm-for-a-recreated-instance) first.

```bash
ssh-add -t 3600 ~/.ssh/vault-laptop
bash scripts/deployment/check-ansible-connectivity.sh
ansible-playbook -i ansible/inventory/private.ini ansible/bootstrap-vault.yml --syntax-check
```

### 3. Run the one-time bootstrap

The playbook itself runs helper preflight on the controller. Preflight assumes the bootstrap role, verifies the AWS role/account, and checks that the recovery secret uses the expected KMS key and has no versions. If it fails, the play stops before initialization.

```bash
ansible-playbook -i ansible/inventory/private.ini ansible/bootstrap-vault.yml --limit vault-node-1
```

At the prompt, type exactly **`INITIALIZE VAULT NODE 1`** only when you intend to initialize. The playbook starts Vault without enabling boot startup, refuses an initialized cluster, and initializes once with five recovery shares and a threshold of three. It sends the captured JSON directly to the controller helper through stdin. Sensitive tasks use `no_log`; do not use `-vvv`, print the JSON, or run `aws secretsmanager get-secret-value`. A successful final task verifies secret-version metadata without reading the stored value.

The single Secrets Manager bundle stores all five recovery shares, the 3-of-5 threshold, and the initial root token. It is encrypted by the dedicated recovery KMS key; Vault EC2 instances do not get access to this secret. The recovery shares are not substitutes for the separate auto-unseal KMS key.

Vault initialization and the Secrets Manager write are not atomic. The captured response exists in controller memory and is not durably staged. If initialization succeeds but storage fails or the controller loses the response, **never rerun initialization**. Stop and assess recovery options; do not assume Vault can return the original recovery shares or root token.

## Current checkpoint and next Raft step

The recovery resources and bdeployootstrap helper/playbook are implemented. Initialization, runtime KMS auto-unseal, Raft joining, three-node HA, NLB listener, and Route 53 access have not been verified in this runbook. Do not expose Vault publicly before initialization. After safe initialization and recovery-bundle verification, validate KMS auto-unseal with a controlled restart, then configure/test NLB and DNS and join followers one at a time. A follower must join the existing cluster; never initialize it separately. See the [Raft HA sequence](raft-ha.md) for the remaining checks.
