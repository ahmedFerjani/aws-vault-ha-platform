#!/usr/bin/env bash
set -euo pipefail

[[ $EUID == 0 ]] || { echo "Run this helper as root (for example: sudo bash ...)" >&2; exit 1; }
id ec2-user >/dev/null
systemctl is-active --quiet sshd || { echo "sshd is not active" >&2; exit 1; }

# Accept only a parseable ED25519 public key; this is not a private key.
read -r -p "Paste the laptop ssh-ed25519 public key: " public_key
[[ ${public_key%% *} == ssh-ed25519 ]] || { echo "Expected an ssh-ed25519 public key" >&2; exit 1; }
blob=$(printf '%s\n' "$public_key" | ssh-keygen -lf /dev/stdin | awk '{print $2}')

# Append the key once with OpenSSH restrictions; preserve other authorized keys.
ssh_dir=/home/ec2-user/.ssh
authorized_keys="$ssh_dir/authorized_keys"
install -d -o ec2-user -g ec2-user -m 700 "$ssh_dir"
touch "$authorized_keys"
chown ec2-user:ec2-user "$authorized_keys"
chmod 600 "$authorized_keys"
if grep -Fqx "restrict $public_key" "$authorized_keys"; then
  echo "Laptop key is already authorized."
elif awk -v blob="$blob" '{ for (i=1; i<=NF; i++) if ($i==blob) found=1 } END { exit !found }' "$authorized_keys"; then
  echo "This key already exists with different options; inspect authorized_keys." >&2
  exit 1
else
  printf 'restrict %s\n' "$public_key" >> "$authorized_keys"
  echo "Laptop key authorized."
fi

# Return only the node's public host key so the laptop can pin it in known_hosts.
echo "Node ED25519 host public key (copy the complete next line):"
cat /etc/ssh/ssh_host_ed25519_key.pub
