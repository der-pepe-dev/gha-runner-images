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

# --- Proxmox helpers ---------------------------------------------------------
# POST to a Proxmox API path; echo the raw JSON response.
pve_post() {
  local path="$1"; shift
  curl -fsS -k -H "$PVE_AUTH" -X POST "${PROXMOX_URL}${path}" "$@"
}

# Wait for a Proxmox task (UPID) to finish with exit status OK.
wait_for_task() {
  local upid="$1" tries=120 body status
  [ -n "$upid" ] && [ "$upid" != "null" ] || return 0
  while [ "$tries" -gt 0 ]; do
    body="$(curl -fsS -k -H "$PVE_AUTH" "${PROXMOX_URL}/nodes/${PROXMOX_NODE}/tasks/${upid}/status" 2>/dev/null)" || true
    status="$(printf '%s' "$body" | jq -r '.data.status // empty')"
    if [ "$status" = "stopped" ]; then
      [ "$(printf '%s' "$body" | jq -r '.data.exitstatus // empty')" = "OK" ] && return 0
      echo "task ${upid} did not exit OK" >&2; return 1
    fi
    sleep 2; tries=$((tries - 1))
  done
  echo "task ${upid} timed out" >&2; return 1
}

# Wait for the QEMU guest agent to respond.
wait_for_agent() {
  local vmid="$1" tries=120
  while [ "$tries" -gt 0 ]; do
    if curl -fsS -k -H "$PVE_AUTH" -X POST \
         "${PROXMOX_URL}/nodes/${PROXMOX_NODE}/qemu/${vmid}/agent/ping" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2; tries=$((tries - 1))
  done
  echo "guest agent on ${vmid} not responding" >&2; return 1
}

# Write a file into the guest via the agent (used to inject the runner env).
pve_agent_write_file() {
  local vmid="$1" path="$2" content="$3"
  curl -fsS -k -H "$PVE_AUTH" -X POST \
    --data-urlencode "file=${path}" \
    --data-urlencode "content=${content}" \
    "${PROXMOX_URL}/nodes/${PROXMOX_NODE}/qemu/${vmid}/agent/file-write" >/dev/null
}

# --- Reset one runner slot (snapshot-rollback + guest-agent token injection) --
# Rolls the slot VM back to its clean (unregistered) snapshot, starts it, mints a
# fresh registration token, and writes the runner env into the guest via the agent.
# A waiter baked into the image reads that env and runs the one-shot ephemeral runner.
reset_runner_slot() {
  local idx="$1"
  local name vmid snapshot os labels upid runner_token runner_url env_path env_content
  eval "name=\${SLOT_${idx}_NAME}"
  eval "vmid=\${SLOT_${idx}_VMID}"
  eval "snapshot=\${SLOT_${idx}_CLEAN_SNAPSHOT:-clean}"
  eval "os=\${SLOT_${idx}_OS}"
  eval "labels=\${SLOT_${idx}_LABELS}"

  echo "Resetting ${name} (vmid ${vmid}): rollback -> '${snapshot}'"

  # 1. Roll back to the clean snapshot.
  upid="$(pve_post "/nodes/${PROXMOX_NODE}/qemu/${vmid}/snapshot/${snapshot}/rollback" | jq -r '.data // empty')"
  wait_for_task "$upid" || { echo "ERR ${name}: rollback failed" >&2; return 1; }

  # 2. Start the VM.
  upid="$(pve_post "/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/start" | jq -r '.data // empty')"
  wait_for_task "$upid" || { echo "ERR ${name}: start failed" >&2; return 1; }

  # 3. Wait for the guest agent.
  wait_for_agent "$vmid" || { echo "ERR ${name}: agent not up" >&2; return 1; }

  # 4. Mint a fresh registration token (orchestrator holds the PAT, not the runner).
  runner_token="$(get_github_runner_token "$GITHUB_OWNER" "$GITHUB_REPO" "$REGISTRATION_SCOPE")"
  if [ -z "$runner_token" ] || [ "$runner_token" = "null" ]; then
    echo "ERR ${name}: token request failed" >&2; return 1
  fi
  if [ "$REGISTRATION_SCOPE" = "org" ]; then
    runner_url="https://github.com/${GITHUB_OWNER}"
  else
    runner_url="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
  fi

  # 5. Inject the runner env via the guest agent (OS-specific path + format).
  if [ "$os" = "windows" ]; then
    env_path='C:\gha-runner\runner.env.ps1'
    env_content="\$env:RUNNER_URL='${runner_url}'
\$env:RUNNER_TOKEN='${runner_token}'
\$env:RUNNER_NAME='${name}'
\$env:RUNNER_LABELS='${labels}'
\$env:RUNNER_EPHEMERAL='true'"
  else
    env_path='/etc/gha-runner/env'
    env_content="RUNNER_URL=${runner_url}
RUNNER_TOKEN=${runner_token}
RUNNER_NAME=${name}
RUNNER_LABELS=${labels}
RUNNER_EPHEMERAL=true"
  fi
  pve_agent_write_file "$vmid" "$env_path" "$env_content" \
    || { echo "ERR ${name}: env injection failed" >&2; return 1; }

  echo "${name}: clean, started, env injected — waiter will register --ephemeral."
  # Don't leave the token in the environment/logs.
  unset runner_token env_content
}

# --- Reconcile loop over this node's slots ------------------------------------
for ((i = 1; i <= SLOT_COUNT; i++)); do
  eval "slot_name=\${SLOT_${i}_NAME:-}"
  eval "slot_vmid=\${SLOT_${i}_VMID:-}"
  if [ -z "$slot_name" ] || [ -z "$slot_vmid" ]; then
    echo "slot ${i}: incomplete config, skipping" >&2; continue
  fi

  if state="$(get_proxmox_vm_state "$slot_vmid" 2>/dev/null)"; then
    echo "${slot_name}: ${state}"
    if [ "$state" = "stopped" ]; then
      reset_runner_slot "$i"
    fi
  else
    echo "WARN ${slot_name}: status check failed (missing VM? clone from template here)" >&2
  fi
done
