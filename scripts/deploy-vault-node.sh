#!/usr/bin/env bash
set -euo pipefail

[[ $# -le 2 ]] || { echo "Usage: $0 [INVENTORY] [HOST_ALIAS]" >&2; exit 2; }
inventory=${1:-ansible/inventory/private.ini}
host=${2:-vault-node-1}
[[ -r $inventory ]] || { echo "Inventory is missing or unreadable: $inventory" >&2; exit 1; }
command -v ansible-playbook >/dev/null || { echo "Missing required command: ansible-playbook" >&2; exit 1; }

script_dir=$(cd "$(dirname "$0")" && pwd)
export ANSIBLE_HOST_KEY_CHECKING=True

# Refuse patterns such as "all" that would expand the deployment beyond one host.
selected_hosts=$(ansible "$host" -i "$inventory" --list-hosts | awk 'NR > 1 && NF { print $1 }')
[[ $selected_hosts == "$host" ]] || {
  echo "Expected exactly the inventory host '$host'; selected: ${selected_hosts:-none}" >&2
  exit 1
}

# Stop before deployment unless syntax, SSH-over-SSM, Python, and become all pass.
ansible-playbook -i "$inventory" "$script_dir/../ansible/site.yml" --syntax-check
bash "$script_dir/check-ansible-connectivity.sh" "$inventory" "$host"

# This role stops/disables Vault, so require a deliberate disposable-node confirmation.
echo "WARNING: the Vault role stops and disables the service on '$host'."
echo "Run only on a disposable, non-serving node; this can interrupt service/quorum."
read -r -p "Type DEPLOY-$host to continue: " confirmation
[[ $confirmation == "DEPLOY-$host" ]] || { echo "Cancelled; playbook was not run."; exit 1; }

# Limit the play to the exact host alias checked above.
exec ansible-playbook -i "$inventory" "$script_dir/../ansible/site.yml" --limit "$host"