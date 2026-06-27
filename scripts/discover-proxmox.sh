#!/usr/bin/env bash
# Discover Proxmox cluster facts and fill the local Packer var files.
#
# Connects to the Proxmox API and detects sensible defaults for the build
# variables, then writes gitignored local var files:
#   packer/windows/local.pkrvars.hcl
#   packer/linux/local.pkrvars.hcl
#
# What it detects (prefers Ceph, since this fleet uses shared Ceph storage):
#   storage_pool      VM-disk storage with `images` content (prefers type rbd)
#   iso_storage_pool  storage with `iso` content (prefers type cephfs)
#   iso_file          a matching install ISO already present in that storage
#   bridge            first Linux bridge (vmbr*) on the node
#   proxmox_node      the queried node (also lists the others as a comment)
#
# Secrets are NOT written by default: the API token and winrm/build passwords are
# left as CHANGE_ME placeholders (pass them via -var / PKR_VAR_* / a separate file,
# or re-run with --include-token to bake the token into the gitignored output).
#
# Dependencies: bash, curl, jq.
#
# Secrets come from the environment, never committed:
#   PROXMOX_TOKEN_ID   e.g. packer@pve!packer
#   PROXMOX_TOKEN      the token secret
#
# Usage:
#   PROXMOX_URL=https://pve01:8006/api2/json \
#   PROXMOX_TOKEN_ID='packer@pve!packer' PROXMOX_TOKEN='...' \
#     scripts/discover-proxmox.sh [--node NODE] [--force] [--include-token]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NODE_OVERRIDE=""
FORCE=0
INCLUDE_TOKEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --node) NODE_OVERRIDE="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --include-token) INCLUDE_TOKEN=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# --- Preconditions -----------------------------------------------------------
: "${PROXMOX_URL:?Set PROXMOX_URL, e.g. https://pve01:8006/api2/json}"
: "${PROXMOX_TOKEN_ID:?Set PROXMOX_TOKEN_ID, e.g. packer@pve!packer}"
: "${PROXMOX_TOKEN:?Set PROXMOX_TOKEN}"
command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"   >&2; exit 1; }

PVE_AUTH="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN}"

# GET a Proxmox API path, return the `.data` array/object. -k: self-signed certs.
pve_get() {
  curl -fsS -k -H "$PVE_AUTH" "${PROXMOX_URL}$1" | jq '.data'
}

echo "Connecting to ${PROXMOX_URL} ..." >&2
if ! pve_get "/version" >/dev/null; then
  echo "Failed to reach the Proxmox API. Check PROXMOX_URL, token, and network." >&2
  exit 1
fi

# --- Nodes -------------------------------------------------------------------
mapfile -t NODES < <(pve_get "/nodes" | jq -r '.[].node' | sort)
[ "${#NODES[@]}" -gt 0 ] || { echo "No nodes returned." >&2; exit 1; }

NODE="${NODE_OVERRIDE:-${NODES[0]}}"
printf 'Nodes: %s\n' "${NODES[*]}" >&2
echo "Using node: ${NODE}" >&2

# --- Storage (cluster-wide defs) ---------------------------------------------
# Each entry: {storage, type, content} where content is a comma list.
STORAGE_JSON="$(pve_get "/storage")"

# VM-disk storage: content has `images`. Prefer Ceph rbd, else first match.
STORAGE_POOL="$(printf '%s' "$STORAGE_JSON" | jq -r '
  [ .[] | select(.content // "" | test("images")) ]
  | (map(select(.type=="rbd")) + .) | .[0].storage // empty')"

# ISO storage: content has `iso`. Prefer cephfs, else first match.
ISO_STORAGE_POOL="$(printf '%s' "$STORAGE_JSON" | jq -r '
  [ .[] | select(.content // "" | test("iso")) ]
  | (map(select(.type=="cephfs")) + .) | .[0].storage // empty')"

echo "Detected storage_pool (VM disk): ${STORAGE_POOL:-<none found>}" >&2
echo "Detected iso_storage_pool:       ${ISO_STORAGE_POOL:-<none found>}" >&2

# --- Bridges -----------------------------------------------------------------
BRIDGE="$(pve_get "/nodes/${NODE}/network" \
  | jq -r '[ .[] | select(.type=="bridge") | .iface ] | sort | .[0] // empty')"
echo "Detected bridge: ${BRIDGE:-<none found>}" >&2

# --- ISOs present ------------------------------------------------------------
# List iso volids in the detected ISO storage (fall back to scanning all storages).
list_isos() {
  local store="$1"
  pve_get "/nodes/${NODE}/storage/${store}/content?content=iso" 2>/dev/null \
    | jq -r '.[].volid' 2>/dev/null || true
}

ISOS=""
if [ -n "$ISO_STORAGE_POOL" ]; then
  ISOS="$(list_isos "$ISO_STORAGE_POOL")"
fi
if [ -z "$ISOS" ]; then
  while read -r s; do
    [ -n "$s" ] && ISOS+="$(list_isos "$s")"$'\n'
  done < <(printf '%s' "$STORAGE_JSON" | jq -r '.[] | select(.content // "" | test("iso")) | .storage')
fi

pick_iso() { printf '%s\n' "$ISOS" | grep -iE "$1" | head -1 || true; }
# 'windows' not 'server' — an Ubuntu "live-server" ISO also contains "server".
WIN_ISO="$(pick_iso 'windows|winserver|win-server')"
LINUX_ISO="$(pick_iso 'ubuntu|debian|linux')"

echo "Windows ISO: ${WIN_ISO:-<none found — upload one>}" >&2
echo "Linux ISO:   ${LINUX_ISO:-<none found — upload one>}" >&2

# --- Emit a value or a CHANGE_ME placeholder with a hint ----------------------
val_or_todo() { [ -n "$1" ] && printf '%s' "$1" || printf 'CHANGE_ME_%s' "$2"; }

if [ "$INCLUDE_TOKEN" -eq 1 ]; then
  TOKEN_LINE="proxmox_token    = \"${PROXMOX_TOKEN}\""
else
  TOKEN_LINE='proxmox_token    = "CHANGE_ME"   # pass via -var/PKR_VAR_proxmox_token, or --include-token'
fi

NODES_COMMENT="# cluster nodes: ${NODES[*]}"

write_varfile() {
  local path="$1" iso="$2" vm_name="$3" is_windows="$4"
  if [ -f "$path" ] && [ "$FORCE" -ne 1 ]; then
    echo "SKIP existing $path (use --force to overwrite)" >&2
    return
  fi
  {
    echo "# Generated by scripts/discover-proxmox.sh on $(date '+%Y-%m-%d %H:%M')."
    echo "# Gitignored local var file — safe to edit. Do not commit."
    echo "$NODES_COMMENT"
    echo ""
    echo "proxmox_url      = \"${PROXMOX_URL}\""
    echo "proxmox_username = \"${PROXMOX_TOKEN_ID}\""
    echo "$TOKEN_LINE"
    echo "proxmox_node     = \"${NODE}\""
    echo ""
    echo "iso_file         = \"$(val_or_todo "$iso" ISO)\""
    echo "storage_pool     = \"$(val_or_todo "$STORAGE_POOL" STORAGE_POOL)\""
    echo "iso_storage_pool = \"$(val_or_todo "$ISO_STORAGE_POOL" ISO_STORAGE_POOL)\""
    echo "bridge           = \"$(val_or_todo "$BRIDGE" BRIDGE)\""
    echo ""
    echo "vm_name          = \"${vm_name}\""
    if [ "$is_windows" -eq 1 ]; then
      echo "winrm_username   = \"Administrator\""
      echo "winrm_password   = \"CHANGE_ME_BUILD_PASSWORD\"   # MUST match autounattend.xml"
    fi
  } >"$path"
  echo "WROTE $path" >&2
}

write_varfile "$REPO_ROOT/packer/windows/local.pkrvars.hcl" "$WIN_ISO"   "tmpl-win-gha-core"    1
write_varfile "$REPO_ROOT/packer/linux/local.pkrvars.hcl"   "$LINUX_ISO" "tmpl-ubuntu-gha-core" 0

echo "" >&2
echo "Done. Review the files, fill any CHANGE_ME values, then:" >&2
echo "  cd packer/windows && packer validate -var-file=local.pkrvars.hcl windows-gha-core.pkr.hcl" >&2
