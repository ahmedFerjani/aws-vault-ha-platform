#!/usr/bin/env bash
set -euo pipefail

[[ $# -le 2 ]] || { echo "Usage: $0 [INVENTORY] [HOST_ALIAS]" >&2; exit 2; }
inventory=${1:-ansible/inventory/private.ini}
host=${2:-vault-node-1}
[[ -r $inventory ]] || { echo "Inventory is missing or unreadable: $inventory" >&2; exit 1; }

command -v ansible >/dev/null || { echo "Missing required command: ansible" >&2; exit 1; }

# Force strict checking so this preflight never accepts an unknown host key.
export ANSIBLE_HOST_KEY_CHECKING=True

# Check SSH-over-SSM authentication and the managed node's Python runtime.
echo "Checking Ansible ping for $host..."
ansible "$host" -i "$inventory" -m ansible.builtin.ping

# Verify become without changing the host; command reports CHANGED by default.
echo "Checking become access (expected effective UID 0)..."
become_output=$(ansible "$host" -i "$inventory" --become -m ansible.builtin.command -a 'id -u')
printf '%s\n' "$become_output"
last_line=$(printf '%s\n' "$become_output" | awk 'NF { line=$0 } END { print line }')
[[ $last_line == 0 ]] || { echo "Become check did not return UID 0; do not run the playbook." >&2; exit 1; }

echo "Preflight passed for $host. No playbook was run."
