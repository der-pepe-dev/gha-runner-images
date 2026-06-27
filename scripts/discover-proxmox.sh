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
# Match Linux bridges, OVS bridges, or anything named vmbr* — covers the common
# setups. Surface a hint if the network query itself failed (e.g. missing perms).
NETWORK_JSON="$(pve_get "/nodes/${NODE}/network" 2>/dev/null || true)"
if [ -z "$NETWORK_JSON" ] || [ "$NETWORK_JSON" = "null" ]; then
  echo "WARN could not read /nodes/${NODE}/network (token perms? needs Sys.Audit)" >&2
  BRIDGE=""
else
  BRIDGE="$(printf '%s' "$NETWORK_JSON" | jq -r '
    [ .[] | select((.type // "" | test("bridge";"i")) or (.iface // "" | test("^vmbr"))) | .iface ]
    | sort | .[0] // empty')"
fi
# Fallback: /nodes/<node>/network does not list SDN VNets (and may hide bridges on
# some setups), so derive the bridge from an existing VM's net config — whatever a
# running VM attaches to is exactly what a new clone should use. Reads `bridge=` from
# net0..net31 of the first non-template VM.
bridge_from_existing_vm() {
  local vms vmid vnode cfg br
  vms="$(pve_get "/cluster/resources?type=vm" 2>/dev/null || true)"
  [ -n "$vms" ] || return 0
  while read -r vmid vnode; do
    if [ -z "$vmid" ] || [ -z "$vnode" ]; then continue; fi
    cfg="$(pve_get "/nodes/${vnode}/qemu/${vmid}/config" 2>/dev/null || true)"
    br="$(printf '%s' "$cfg" | jq -r '[to_entries[] | select(.key|test("^net[0-9]+$")) | .value] | .[]?' 2>/dev/null \
          | grep -oE 'bridge=[^,]+' | head -1 | cut -d= -f2)"
    if [ -n "$br" ]; then printf '%s' "$br"; return 0; fi
  done < <(printf '%s' "$vms" | jq -r '.[] | select(.template != 1) | "\(.vmid) \(.node)"')
}

if [ -z "$BRIDGE" ]; then
  echo "Detected bridge: <none in node network list> — checking existing VMs ..." >&2
  if [ -n "$NETWORK_JSON" ]; then
    echo "  network entries returned: $(printf '%s' "$NETWORK_JSON" | jq -rc 'if type=="array" then [.[]|{iface,type}] else . end' 2>/dev/null)" >&2
  fi
  BRIDGE="$(bridge_from_existing_vm)"
  if [ -n "$BRIDGE" ]; then
    echo "  bridge from an existing VM: ${BRIDGE}" >&2
  else
    echo "  no VM net config readable — defaulting to vmbr0 (verify)" >&2
    BRIDGE="vmbr0"
  fi
else
  echo "Detected bridge: ${BRIDGE}" >&2
fi

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

# Match Linux distros first, then treat anything Windows-ish that ISN'T a Linux
# distro as the Windows ISO. This catches MS eval names like
# "SERVER_EVAL_x64FREE_en-us.iso" (no "windows" in the name) without grabbing an
# Ubuntu "live-server" ISO (which also contains "server").
LINUX_PAT='ubuntu|debian|fedora|rocky|almalinux|alma|centos|opensuse'
WIN_PAT='windows|winserver|server|_eval_|x64free'
LINUX_ISO="$(printf '%s\n' "$ISOS" | grep -iE "$LINUX_PAT" | head -1 || true)"
WIN_ISO="$(printf '%s\n' "$ISOS" | grep -iE "$WIN_PAT" | grep -ivE "$LINUX_PAT" | head -1 || true)"

echo "Windows ISO: ${WIN_ISO:-<none found — upload one>}" >&2
echo "Linux ISO:   ${LINUX_ISO:-<none found — upload one>}" >&2

# --- Emit a value or a CHANGE_ME placeholder with a hint ----------------------
val_or_todo() { [ -n "$1" ] && printf '%s' "$1" || printf 'CHANGE_ME_%s' "$2"; }

if [ "$INCLUDE_TOKEN" -eq 1 ]; then
  TOKEN_LINE="proxmox_token    = \"${PROXMOX_TOKEN}\""
else
  # Leave proxmox_token UNSET in the file: a -var-file value would override the
  # PKR_VAR_proxmox_token env var (Packer precedence), so an assignment here would
  # shadow the env/-var token and cause a 401. Pass the secret at build time instead.
  # shellcheck disable=SC2016  # literal $PROXMOX_TOKEN is intentional doc text
  TOKEN_LINE='# proxmox_token: set at build time via `-var "proxmox_token=$PROXMOX_TOKEN"`'
  TOKEN_LINE="$TOKEN_LINE"$'\n#               or env PKR_VAR_proxmox_token, or re-run with --include-token'
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

# --- Fleet definition (scripts/fleet.local.yml) ------------------------------
# Find template VMIDs cluster-wide by name. Templates on Ceph are visible from any
# node, but each is owned by the node it was built on; /cluster/resources lists all.
RESOURCES_JSON="$(pve_get "/cluster/resources?type=vm")"

template_vmid_by_name() {
  # arg: a regex matched against the template name (case-insensitive)
  printf '%s' "$RESOURCES_JSON" \
    | jq -r --arg re "$1" '[ .[] | select(.template==1) | select(.name|test($re;"i")) ] | .[0].vmid // empty'
}

WIN_TMPL_VMID="$(template_vmid_by_name 'win-gha-core')"
LINUX_TMPL_VMID="$(template_vmid_by_name 'ubuntu-gha-core|linux-gha')"
ORCH_TMPL_VMID="$(template_vmid_by_name 'orch')"

echo "Windows template VMID: ${WIN_TMPL_VMID:-<not built yet>}" >&2
echo "Linux template VMID:   ${LINUX_TMPL_VMID:-<not built yet>}" >&2

FLEET_FILE="$REPO_ROOT/scripts/fleet.local.yml"
if [ -z "$WIN_TMPL_VMID" ] && [ -z "$LINUX_TMPL_VMID" ]; then
  echo "SKIP $FLEET_FILE: no gha templates found yet — build them, then re-run." >&2
elif [ -f "$FLEET_FILE" ] && [ "$FORCE" -ne 1 ]; then
  echo "SKIP existing $FLEET_FILE (use --force to overwrite)" >&2
else
  RBD="$(val_or_todo "$STORAGE_POOL" STORAGE_POOL)"
  {
    echo "# Generated by scripts/discover-proxmox.sh on $(date '+%Y-%m-%d %H:%M')."
    echo "# Gitignored local fleet definition for scripts/clone-runner-fleet.ps1."
    echo "# One Linux + one Windows runner (and an optional orchestrator) per node."
    echo ""
    echo "proxmox_url: \"${PROXMOX_URL}\""
    echo "windows_template_vmid: $(val_or_todo "$WIN_TMPL_VMID" WIN_TEMPLATE_VMID)"
    echo "linux_template_vmid: $(val_or_todo "$LINUX_TMPL_VMID" LINUX_TEMPLATE_VMID)"
    echo "orchestrator_template_vmid: $(val_or_todo "$ORCH_TMPL_VMID" ORCH_TEMPLATE_VMID)"
    echo "storage: \"${RBD}\""
    echo "full_clone: true"
    echo ""
    echo "orchestrators:"
    n=0
    for node in "${NODES[@]}"; do
      n=$((n + 1))
      printf '  - name: gha-orch%02d\n    node: %s\n    vmid: %d\n    manages:\n      - gha-linux%02d\n      - gha-win%02d\n' \
        "$n" "$node" $((290 + n)) "$n" "$n"
    done
    echo ""
    echo "runners:"
    n=0
    for node in "${NODES[@]}"; do
      n=$((n + 1))
      printf '  - name: gha-linux%02d\n    node: %s\n    vmid: %d\n    template: linux\n    labels: "self-hosted,linux,x64,dotnet10,proxmox,%s,ephemeral"\n' \
        "$n" "$node" $((300 + n)) "$node"
      printf '  - name: gha-win%02d\n    node: %s\n    vmid: %d\n    template: windows\n    labels: "self-hosted,windows,x64,dotnet10,proxmox,%s,ephemeral"\n' \
        "$n" "$node" $((310 + n)) "$node"
    done
  } >"$FLEET_FILE"
  echo "WROTE $FLEET_FILE" >&2
fi

echo "" >&2
echo "Done. Review the files, fill any CHANGE_ME values, then:" >&2
echo "  cd packer/windows && packer validate -var-file=local.pkrvars.hcl windows-gha-core.pkr.hcl" >&2
