# Vault installation and node access

## Current design

Terraform launches Vault EC2 instances in private subnets. The laptop is the Ansible controller. SSH is tunneled to each instance through Systems Manager `AWS-StartSSHSession`; this is ordinary SSH over SSM, not Ansible's native SSM connection plugin. No management EC2 host, public node IP, or inbound TCP 22 rule is required.

The access layers are separate:

1. IAM authorizes the operator to start an SSM session; SSM carries the network tunnel.
2. The laptop's private SSH key authenticates `ec2-user`. Only its public key is installed on the node.
3. The node's SSH host public key is verified and pinned in laptop `known_hosts` under the EC2 instance ID.

Session Manager does not record SSH command contents inside the tunnel. CloudTrail can record session API activity; use host and Vault audit controls for command/API auditing. Never disable SSH host-key checking or TLS verification to work around trust errors.

## Workflow at a glance

For a newly created or recreated node, use this order: (1) review and apply Terraform; (2) update the ignored inventory with the new instance ID; (3) run `ansible/access-vault-node.yml` to set up SSH-over-SSM through its local helper; (4) run `ansible/deploy-vault-node.yml` to check access and install/configure Vault; (5) prepare the controller and run `ansible/bootstrap-vault.yml` once. Do not run the deployment playbook against an initialized or serving node: the role stops and disables Vault.

## Prerequisites

- Laptop: Bash, AWS CLI, Session Manager plugin, OpenSSH tools, Ansible, and access to the TLS certificate chain and matching private key.
- AWS: operator credentials with access to describe the target, use `ssm:SendCommand` with `AWS-RunShellScript` on that instance, retrieve the command result, and start the `AWS-StartSSHSession` tunnel used by Ansible.
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

Update `ansible/inventory/private.ini` with the new instance ID, then run this playbook from the repository root:

```bash
ansible-playbook -i ansible/inventory/private.ini ansible/access-vault-node.yml --limit vault-node-1
```

The playbook verifies that exactly `vault-node-1` is targeted, then delegates the local helper to the controller without a separate confirmation prompt. The helper verifies that EC2 is running and SSM is online, reuses or creates `~/.ssh/vault-laptop`, and uses SSM Run Command to add only the laptop public key to `ec2-user` and retrieve the instance's ED25519 host public key. It pins that key under the instance ID in `known_hosts`, refusing a fingerprint conflict. No inbound SSH rule or manual script paste is needed. The helper still requires explicit confirmation when run directly outside Ansible.

The AWS identity needs permissions to describe the instance and SSM registration, send `AWS-RunShellScript` to the target, retrieve the command invocation result, and start the `AWS-StartSSHSession` tunnel. The helper is invoked by Ansible; operators do not run it directly. `scripts/access/authorize-ssm-ssh-node.sh` remains an optional manual fallback for a trusted interactive SSM shell.

## Load the laptop SSH key

Load the key into the SSH agent for one hour. Enter its passphrase locally if prompted; Ansible uses the agent and does not need the passphrase.

```bash
ssh-add -t 3600 ~/.ssh/vault-laptop
```

## Deploy Vault to one node

Review the inventory and verify that the TLS certificate and private key exist, match, and are valid for `vault.ahmedferjani.com`. Then syntax-check and run the deployment playbook:

```bash
ansible-playbook -i ansible/inventory/private.ini ansible/deploy-vault-node.yml --limit vault-node-1 --syntax-check
ansible-playbook -i ansible/inventory/private.ini ansible/deploy-vault-node.yml --limit vault-node-1
```

The playbook checks SSH/ping and effective root access, then asks you to type `DEPLOY VAULT NODE 1`. Review the inventory target and TLS source paths first. It is restricted to `vault-node-1` and installs/configures the role directly; it does not initialize Vault.

**The Ansible role stops and disables `vault.service`.** Run it only on a disposable, non-serving node; applying it to a serving cluster can interrupt service and quorum. Missing TLS files can cause partial installation because package tasks precede TLS checks. Run the playbook again only on a disposable, non-serving node to test idempotency; a converged node should report `changed=0`, `failed=0`, and `unreachable=0`. Installation does not start or initialize Vault.

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

## Current checkpoint

The operator reports a healthy single-node Vault endpoint, with initialization, recovery storage, restart auto-unseal, NLB, and DNS checks completed. This is not HA: followers, three-node quorum, failover, replacement, and restore testing remain. Current Ansible entry points are `ansible/access-vault-node.yml`, `ansible/deploy-vault-node.yml`, and the one-time `ansible/bootstrap-vault.yml`. See [Raft HA](raft-ha.md) for the cluster plan. Never run the deployment playbook on this initialized node; its role stops and disables Vault.
