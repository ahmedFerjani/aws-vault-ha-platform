#!/usr/bin/env bash
set -euo pipefail

[[ $# -ge 1 && $# -le 2 ]] || { echo "Usage: $0 INSTANCE_ID [REGION]" >&2; exit 2; }
instance_id=$1
region=${2:-us-east-1}
[[ $instance_id =~ ^i-[0-9a-f]+$ ]] || { echo "Invalid EC2 instance ID" >&2; exit 2; }

for tool in aws ssh-keygen awk sort sed python3; do
  command -v "$tool" >/dev/null || { echo "Missing required command: $tool" >&2; exit 1; }
done

# Check EC2 and SSM readiness before preparing access for this instance.
state=$(aws ec2 describe-instances --region "$region" --instance-ids "$instance_id" --query 'Reservations[0].Instances[0].State.Name' --output text)
[[ $state == running ]] || { echo "Instance is $state, not running" >&2; exit 1; }
ssm_status=$(aws ssm describe-instance-information --region "$region" --filters "Key=InstanceIds,Values=$instance_id" --query 'InstanceInformationList[0].PingStatus' --output text)
[[ $ssm_status == Online ]] || { echo "SSM status is $ssm_status, not Online" >&2; exit 1; }

# Reuse the dedicated laptop key; create it only when neither half exists.
key="$HOME/.ssh/vault-laptop"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [[ ! -e $key && ! -e $key.pub ]]; then
  ssh-keygen -t ed25519 -a 64 -f "$key" -C vault-laptop
elif [[ ! -r $key ]]; then
  echo "Private key is missing or unreadable: $key (refusing to overwrite)" >&2
  exit 1
fi
chmod 600 "$key"
if [[ ! -r $key.pub ]]; then
  ssh-keygen -y -f "$key" > "$key.pub"
fi
ssh-keygen -lf "$key.pub" >/dev/null

read -r key_type key_blob _ < "$key.pub"
[[ $key_type == ssh-ed25519 && $key_blob =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || {
  echo "Expected one valid ED25519 public key in $key.pub" >&2
  exit 1
}

echo "This will add the laptop public key to ec2-user through SSM Run Command and pin the instance host key."
if [[ -n ${VAULT_ACCESS_CONFIRM:-} ]]; then
  confirmation=$VAULT_ACCESS_CONFIRM
else
  read -r -p "Type AUTHORIZE SSH FOR $instance_id to continue: " confirmation
fi
[[ $confirmation == "AUTHORIZE SSH FOR $instance_id" ]] || {
  echo "Cancelled; no SSM command was sent."
  exit 1
}

# Only the validated public-key blob is interpolated into the remote script.
remote_script=$(cat <<EOF
set -eu
id ec2-user >/dev/null
systemctl is-active --quiet sshd
ssh_dir=/home/ec2-user/.ssh
authorized_keys="\$ssh_dir/authorized_keys"
install -d -o ec2-user -g ec2-user -m 700 "\$ssh_dir"
touch "\$authorized_keys"
chown ec2-user:ec2-user "\$authorized_keys"
chmod 600 "\$authorized_keys"
key_blob='$key_blob'
if grep -Fqx "restrict ssh-ed25519 \$key_blob" "\$authorized_keys"; then
  echo "Laptop key already authorized."
elif awk -v blob="\$key_blob" '{ for (i=1; i<=NF; i++) if (\$i==blob) found=1 } END { exit !found }' "\$authorized_keys"; then
  echo "This key already exists with different options; inspect authorized_keys." >&2
  exit 1
else
  printf 'restrict ssh-ed25519 %s\\n' "\$key_blob" >> "\$authorized_keys"
  chown ec2-user:ec2-user "\$authorized_keys"
  echo "Laptop key authorized."
fi
printf 'VAULT_HOST_KEY: '
cat /etc/ssh/ssh_host_ed25519_key.pub
EOF
)

request=$(python3 -c 'import json,sys; print(json.dumps({"DocumentName":"AWS-RunShellScript","InstanceIds":[sys.argv[1]],"Parameters":{"commands":[sys.argv[2]]}}))' "$instance_id" "$remote_script")
command_id=$(aws ssm send-command --region "$region" --cli-input-json "$request" --query 'Command.CommandId' --output text)
[[ $command_id =~ ^[0-9a-fA-F-]+$ ]] || { echo "SSM did not return a valid command ID" >&2; exit 1; }

echo "Waiting for SSM key authorization command to complete..."
wait_status=0
aws ssm wait command-executed --region "$region" --command-id "$command_id" --instance-id "$instance_id" || wait_status=$?
invocation=$(aws ssm get-command-invocation --region "$region" --command-id "$command_id" --instance-id "$instance_id" --output json)
command_status=$(printf '%s' "$invocation" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Status", "Unknown"))')
command_stdout=$(printf '%s' "$invocation" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("StandardOutputContent", ""), end="")')
command_stderr=$(printf '%s' "$invocation" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("StandardErrorContent", ""), end="")')
if [[ $command_status != Success || $wait_status -ne 0 ]]; then
  echo "SSM authorization command failed with status: $command_status" >&2
  [[ -z $command_stderr ]] || printf '%s\n' "$command_stderr" >&2
  exit 1
fi

# Pin the host key returned by this authenticated SSM command; reject changes.
host_key=$(printf '%s\n' "$command_stdout" | sed -n 's/^VAULT_HOST_KEY: //p')
[[ ${host_key%% *} == ssh-ed25519 ]] || { echo "Expected an ED25519 host public key" >&2; exit 1; }
new_fingerprint=$(printf '%s\n' "$host_key" | ssh-keygen -lf /dev/stdin | awk '{print $2}')
known_hosts="$HOME/.ssh/known_hosts"
touch "$known_hosts"
chmod 600 "$known_hosts"
old_fingerprints=$(ssh-keygen -F "$instance_id" -f "$known_hosts" -l 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i ~ /^SHA256:/) print $i}' | sort -u || true)
if [[ -n $old_fingerprints && $old_fingerprints != "$new_fingerprint" ]]; then
  echo "Host-key conflict for $instance_id; investigate instead of replacing known_hosts." >&2
  exit 1
fi
if [[ -z $old_fingerprints ]]; then
  printf '%s %s\n' "$instance_id" "$host_key" >> "$known_hosts"
fi

echo "Host key is trusted for $instance_id ($new_fingerprint)."
echo "Next: ssh-add -t 3600 '$key', then run ansible/deploy-vault-node.yml with the intended inventory limit."
