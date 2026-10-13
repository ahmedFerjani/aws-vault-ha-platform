#!/usr/bin/env bash
set -euo pipefail

[[ $# -ge 1 && $# -le 2 ]] || { echo "Usage: $0 INSTANCE_ID [REGION]" >&2; exit 2; }
instance_id=$1
region=${2:-us-east-1}
[[ $instance_id =~ ^i-[0-9a-f]+$ ]] || { echo "Invalid EC2 instance ID" >&2; exit 2; }

for tool in aws ssh-keygen awk sort; do
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

echo
echo "Laptop public key (copy this line into the node helper in your SSM session):"
cat "$key.pub"
echo
echo "After the node helper prints its ED25519 host public key, paste the full line below."

# Pin the host key copied from the trusted SSM shell; reject unexpected changes.
read -r -p "Node host public key: " host_key
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
echo "Next: ssh-add -t 3600 '$key', then run the Ansible ping and become checks."