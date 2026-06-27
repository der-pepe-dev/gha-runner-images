#!/usr/bin/env bash
# Skeleton local runner orchestrator for one Proxmox node (bash port).
#
# Intended to run from gha-orch01/02/03 as a systemd timer. Each instance manages
# only the runner VMs on its own Proxmox node.
#
# This is a SCAFFOLD, not production-ready code. Fill in the Proxmox status,
# rollback/reclone, and bootstrap-injection pieces to match your actual
# Proxmox/storage/networking workflow. The token-request and slot-iteration logic
# is real; the reset strategy is left as TODO on purpose.
#
# Dependencies (intentionally minimal — keep the orchestrator LXC lean):
#   bash, curl, jq        (no PowerShell, no YAML parser)
#
# Secrets come from the environment (systemd EnvironmentFile), never the config:
#   PROXMOX_TOKEN_ID, PROXMOX_TOKEN, GITHUB_TOKEN
#
# Usage:
#   gha-local-orchestrator.sh [config-file]
# Default config: ./node.local.env (next to this script).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/node.local.env}"

# --- Preconditions -----------------------------------------------------------
: "${PROXMOX_TOKEN_ID:?Set PROXMOX_TOKEN_ID}"
: "${PROXMOX_TOKEN:?Set PROXMOX_TOKEN}"
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN}"
command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found" >&2; exit 1; }
[ -f "$CONFIG_FILE" ] || { echo "Config file not found: $CONFIG_FILE" >&2; exit 1; }

# Flat, shell-sourceable config (SLOT_COUNT + indexed SLOT_<n>_* vars).
# shellcheck source=/dev/null
source "$CONFIG_FILE"

: "${PROXMOX_URL:?Set PROXMOX_URL in config}"
: "${PROXMOX_NODE:?Set PROXMOX_NODE in config}"
: "${SLOT_COUNT:?Set SLOT_COUNT in config}"

PVE_AUTH="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN}"

# --- GitHub: request a fresh short-lived runner registration token ------------
get_github_runner_token() {
  local owner="$1" repo="$2" scope="$3" uri
  if [ "$scope" = "org" ]; then
    uri="https://api.github.com/orgs/${owner}/actions/runners/registration-token"
  else
    uri="https://api.github.com/repos/${owner}/${repo}/actions/runners/registration-token"
  fi
  # --fail so HTTP errors are caught; -s quiet; token parsed with jq.
  curl -fsS -X POST "$uri" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
  | jq -r '.token'
}

# --- Proxmox: current status of a VM -----------------------------------------
get_proxmox_vm_state() {
  local vmid="$1"
  curl -fsS -k \
    -H "$PVE_AUTH" \
    "${PROXMOX_URL}/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/current" \
  | jq -r '.data.status'
}

# --- Reset one runner slot (SCAFFOLD) ----------------------------------------
reset_runner_slot() {
  local idx="$1"
  local name vmid template_vmid snapshot os labels
  eval "name=\${SLOT_${idx}_NAME}"
  eval "vmid=\${SLOT_${idx}_VMID}"
  eval "template_vmid=\${SLOT_${idx}_TEMPLATE_VMID}"
  eval "snapshot=\${SLOT_${idx}_CLEAN_SNAPSHOT}"
  eval "os=\${SLOT_${idx}_OS}"
  eval "labels=\${SLOT_${idx}_LABELS}"

  echo "Resetting slot ${name} on ${PROXMOX_NODE} (mode=${MODE:-unset})"

  # TODO: choose one strategy based on $MODE:
  # 1. snapshot-rollback:
  #    POST {PROXMOX_URL}/nodes/{node}/qemu/{vmid}/snapshot/{snapshot}/rollback
  # 2. destroy-reclone:
  #    DELETE {PROXMOX_URL}/nodes/{node}/qemu/{vmid}
  #    POST   {PROXMOX_URL}/nodes/{node}/qemu/{template_vmid}/clone

  local runner_token
  runner_token="$(get_github_runner_token "$GITHUB_OWNER" "$GITHUB_REPO" "$REGISTRATION_SCOPE")"

  # TODO: inject bootstrap settings into the VM before start. Approaches:
  # - cloud-init custom user-data (Linux)
  # - QEMU guest agent file write (already-booted VMs)
  # - temporary ISO/snippet with an env file
  #
  # Values to inject (do NOT log runner_token):
  #   RUNNER_NAME="$name"
  #   RUNNER_LABELS="$labels"
  #   RUNNER_TOKEN="$runner_token"
  #   RUNNER_EPHEMERAL=true
  #   RUNNER_OS="$os"

  # TODO: start VM:
  #   POST {PROXMOX_URL}/nodes/{node}/qemu/{vmid}/status/start

  echo "Prepared fresh token for ${name}; implement injection/start workflow."
  # Avoid leaking the token in logs/CI output:
  unset runner_token
}

# --- Reconcile loop over this node's slots ------------------------------------
for ((i = 1; i <= SLOT_COUNT; i++)); do
  eval "slot_name=\${SLOT_${i}_NAME:-}"
  eval "slot_vmid=\${SLOT_${i}_VMID:-}"
  [ -n "$slot_name" ] && [ -n "$slot_vmid" ] || { echo "slot ${i}: incomplete config, skipping" >&2; continue; }

  if state="$(get_proxmox_vm_state "$slot_vmid" 2>/dev/null)"; then
    echo "${slot_name}: ${state}"
    if [ "$state" = "stopped" ]; then
      reset_runner_slot "$i"
    fi
  else
    echo "WARN ${slot_name}: status check failed (missing VM? clone from template here)" >&2
  fi
done
