#!/usr/bin/env bash
# Read-only Proxmox VE status for the GHA runner fleet.
#
# Uses the same env-based token as the orchestrator / discover-proxmox.sh:
#   PROXMOX_URL       e.g. https://192.168.0.1:8006/api2/json
#   PROXMOX_TOKEN_ID  e.g. packer@pve!packer
#   PROXMOX_TOKEN     the token secret
# Self-signed certs are accepted (-k), matching the rest of the stack.
#
# Usage:
#   pve-status.sh                 # cluster overview: nodes + all VMs/templates
#   pve-status.sh templates       # just the templates (gha-*)
#   pve-status.sh vm <vmid>       # one VM: status, agent, snapshots, key config
#   pve-status.sh snapshots <vmid>
#   pve-status.sh agent <vmid>    # agent ping + IPv4 addresses
set -euo pipefail

: "${PROXMOX_URL:?Set PROXMOX_URL}"
: "${PROXMOX_TOKEN_ID:?Set PROXMOX_TOKEN_ID}"
: "${PROXMOX_TOKEN:?Set PROXMOX_TOKEN}"
command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"   >&2; exit 1; }

AUTH="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN}"
get()  { curl -fsS -k -H "$AUTH" "${PROXMOX_URL}$1"; }
post() { curl -fsS -k -H "$AUTH" -X POST "${PROXMOX_URL}$1"; }

# Resolve a VM's node from /cluster/resources.
node_of() {
  get "/cluster/resources?type=vm" | jq -r --arg id "$1" '.data[] | select(.vmid==($id|tonumber)) | .node' | head -1
}

overview() {
  echo "# Nodes"
  get "/nodes" | jq -r '.data[] | "  \(.node)  \(.status)  cpu=\((.cpu*100|floor))%  mem=\((.mem/1073741824)|floor)/\((.maxmem/1073741824)|floor)GB"'
  echo
  echo "# VMs / templates (vmid  name  node  status  tmpl)"
  get "/cluster/resources?type=vm" \
    | jq -r '.data | sort_by(.vmid)[] | "  \(.vmid)\t\(.name)\t\(.node)\t\(.status)\t\(if .template==1 then "TEMPLATE" else "" end)"' \
    | column -t -s $'\t'
}

templates() {
  echo "# Templates"
  get "/cluster/resources?type=vm" \
    | jq -r '.data | map(select(.template==1)) | sort_by(.vmid)[] | "  \(.vmid)\t\(.name)\t\(.node)"' \
    | column -t -s $'\t'
}

snapshots() {
  local vmid="$1" node; node="$(node_of "$vmid")"
  [ -n "$node" ] || { echo "vm $vmid not found" >&2; return 1; }
  echo "# Snapshots for $vmid (node $node)"
  get "/nodes/${node}/qemu/${vmid}/snapshot" \
    | jq -r '.data[] | "  \(.name)\t\(.description // "")"' | column -t -s $'\t'
}

agent() {
  local vmid="$1" node; node="$(node_of "$vmid")"
  [ -n "$node" ] || { echo "vm $vmid not found" >&2; return 1; }
  if post "/nodes/${node}/qemu/${vmid}/agent/ping" >/dev/null 2>&1; then
    echo "agent: responding"
    post "/nodes/${node}/qemu/${vmid}/agent/network-get-interfaces" 2>/dev/null \
      | jq -r '.data.result[]? | ."ip-addresses"[]? | select(."ip-address-type"=="ipv4") | "  ip: \(."ip-address")"' \
      | grep -v '127.0.0.1' || true
  else
    echo "agent: not responding"
  fi
}

vm() {
  local vmid="$1" node; node="$(node_of "$vmid")"
  [ -n "$node" ] || { echo "vm $vmid not found" >&2; return 1; }
  echo "# VM $vmid (node $node)"
  get "/nodes/${node}/qemu/${vmid}/status/current" \
    | jq -r '.data | "  status: \(.status)   uptime: \(.uptime // 0)s   tmpl: \(.template // 0)"'
  get "/nodes/${node}/qemu/${vmid}/config" \
    | jq -r '.data | "  cpu: \(.cpu // "default")   scsihw: \(.scsihw // "-")   net0: \(.net0 // "-")   meta: \(.meta // "-")"'
  echo; agent "$vmid"
  echo; snapshots "$vmid"
}

case "${1:-overview}" in
  overview)  overview ;;
  templates) templates ;;
  vm)        vm "${2:?vmid required}" ;;
  snapshots) snapshots "${2:?vmid required}" ;;
  agent)     agent "${2:?vmid required}" ;;
  *) echo "unknown command: $1" >&2; exit 2 ;;
esac
