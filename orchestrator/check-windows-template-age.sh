#!/usr/bin/env bash
# Windows template eval-age check for one Proxmox node.
#
# Windows Server is installed from an EVALUATION ISO, so its activation clock
# (180 days for Server 2022) starts when the template VM is built. This check
# reports how old each Windows runner template is and warns before the eval
# period expires, so the template can be regenerated (or rearmed) in time.
#
# Alert-only: it never rebuilds anything. Run it from the orchestrator on a daily
# systemd timer (gha-template-age-check.timer). Findings go to stdout/journald;
# a non-zero exit means at least one template is at/over the threshold.
#
# Activation time is read from Proxmox: the template VM's `meta` config line
# carries `ctime=<epoch>` (VM creation ≈ OS install ≈ eval start). No state file.
#
# Dependencies: bash, curl, jq (same as the orchestrator LXC).
#
# Secrets come from the environment (systemd EnvironmentFile), never the config:
#   PROXMOX_TOKEN_ID, PROXMOX_TOKEN
#
# Usage:
#   check-windows-template-age.sh [config-file]
# Default config: ./node.local.env (next to this script).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/node.local.env}"

# --- Preconditions -----------------------------------------------------------
: "${PROXMOX_TOKEN_ID:?Set PROXMOX_TOKEN_ID}"
: "${PROXMOX_TOKEN:?Set PROXMOX_TOKEN}"
command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"   >&2; exit 1; }
[ -f "$CONFIG_FILE" ] || { echo "Config file not found: $CONFIG_FILE" >&2; exit 1; }

# shellcheck source=/dev/null
source "$CONFIG_FILE"

: "${PROXMOX_URL:?Set PROXMOX_URL in config}"
: "${PROXMOX_NODE:?Set PROXMOX_NODE in config}"
: "${SLOT_COUNT:?Set SLOT_COUNT in config}"

# Warn threshold and the assumed eval window. Override in node.local.env.
WIN_TEMPLATE_EVAL_MAX_DAYS="${WIN_TEMPLATE_EVAL_MAX_DAYS:-100}"
WIN_TEMPLATE_EVAL_PERIOD_DAYS="${WIN_TEMPLATE_EVAL_PERIOD_DAYS:-180}"

PVE_AUTH="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN}"

# --- Proxmox: creation epoch (ctime) of a VM from its config meta -------------
# Returns the ctime epoch on stdout, or empty if unavailable.
get_vm_ctime() {
  local vmid="$1" meta
  meta="$(curl -fsS -k -H "$PVE_AUTH" \
    "${PROXMOX_URL}/nodes/${PROXMOX_NODE}/qemu/${vmid}/config" \
    | jq -r '.data.meta // empty')" || return 1
  # meta example: "creation-qemu=8.1.2,ctime=1700000000"
  printf '%s' "$meta" | grep -oE 'ctime=[0-9]+' | cut -d= -f2
}

# --- Collect unique Windows template VMIDs from the slot config ---------------
declare -A seen_templates=()
windows_template_vmids=()
for ((i = 1; i <= SLOT_COUNT; i++)); do
  os=""; tmpl=""
  eval "os=\${SLOT_${i}_OS:-}"
  eval "tmpl=\${SLOT_${i}_TEMPLATE_VMID:-}"
  [ "$os" = "windows" ] || continue
  [ -n "$tmpl" ] || continue
  [ -n "${seen_templates[$tmpl]:-}" ] && continue
  seen_templates[$tmpl]=1
  windows_template_vmids+=("$tmpl")
done

if [ "${#windows_template_vmids[@]}" -eq 0 ]; then
  echo "No Windows runner templates configured on ${PROXMOX_NODE}; nothing to check."
  exit 0
fi

now_epoch="$(date +%s)"
overdue=0

for vmid in "${windows_template_vmids[@]}"; do
  ctime="$(get_vm_ctime "$vmid" || true)"
  if [ -z "$ctime" ]; then
    echo "WARN template ${vmid} on ${PROXMOX_NODE}: no ctime in Proxmox meta; cannot determine eval age" >&2
    overdue=1
    continue
  fi

  age_days=$(( (now_epoch - ctime) / 86400 ))
  remaining=$(( WIN_TEMPLATE_EVAL_PERIOD_DAYS - age_days ))
  built="$(date -d "@${ctime}" '+%Y-%m-%d' 2>/dev/null || echo "epoch ${ctime}")"

  if [ "$age_days" -ge "$WIN_TEMPLATE_EVAL_MAX_DAYS" ]; then
    echo "OVERDUE template ${vmid} on ${PROXMOX_NODE}: built ${built}, age ${age_days}d" \
         ">= ${WIN_TEMPLATE_EVAL_MAX_DAYS}d (eval ~${remaining}d left). Regenerate win-gha-core or rearm." >&2
    overdue=1
  else
    echo "OK template ${vmid} on ${PROXMOX_NODE}: built ${built}, age ${age_days}d" \
         "(< ${WIN_TEMPLATE_EVAL_MAX_DAYS}d, eval ~${remaining}d left)."
  fi
done

exit "$overdue"
