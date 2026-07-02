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

# --- GitHub: generate a JIT (just-in-time) runner config ----------------------
# Returns the base64 encoded_jit_config. The runner runs `run.sh --jitconfig <blob>`
# directly — no config.sh, no registration token on disk, inherently single-use +
# ephemeral. The PAT (GITHUB_TOKEN) stays here; the runner only ever sees the one-shot
# encoded config.
generate_jitconfig() {
  local owner="$1" repo="$2" scope="$3" name="$4" labels_csv="$5" uri labels_json body
  if [ "$scope" = "org" ]; then
    uri="https://api.github.com/orgs/${owner}/actions/runners/generate-jitconfig"
  else
    uri="https://api.github.com/repos/${owner}/${repo}/actions/runners/generate-jitconfig"
  fi
  labels_json="$(printf '%s' "$labels_csv" | jq -R 'split(",")')"
  body="$(jq -n --arg name "$name" --argjson labels "$labels_json" \
    '{name:$name, runner_group_id:1, labels:$labels, work_folder:"_work"}')"
  curl -fsS -X POST "$uri" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d "$body" \
  | jq -r '.encoded_jit_config // empty'
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

# --- Reset one runner slot (snapshot-rollback + JIT config injection) ----------
# Rolls the slot VM back to its clean snapshot, starts it, generates a JIT runner
# config, and writes it into the guest via the agent. A waiter baked into the image
# runs `run.sh --jitconfig <blob>` — one job, then shuts down. The PAT stays here.
reset_runner_slot() {
  local idx="$1"
  local name vmid snapshot os labels upid jitconfig env_path env_content
  eval "name=\${SLOT_${idx}_NAME}"
  eval "vmid=\${SLOT_${idx}_VMID}"
  eval "snapshot=\${SLOT_${idx}_CLEAN_SNAPSHOT:-clean}"
  eval "os=\${SLOT_${idx}_OS}"
  eval "labels=\${SLOT_${idx}_LABELS}"

  echo "Resetting ${name} (vmid ${vmid}): rollback -> '${snapshot}'"

  # 1. Roll back to the clean snapshot.
  upid="$(pve_post "/nodes/${PROXMOX_NODE}/qemu/${vmid}/snapshot/${snapshot}/rollback" | jq -r '.data // empty')"
  wait_for_task "$upid" || { echo "ERR ${name}: rollback failed" >&2; return 1; }

  # 2. A vmstate (RAM) snapshot resumes the VM to 'running' ASYNCHRONOUSLY after the
  #    rollback task returns — restoring a live, agent-up, waiter-polling VM in seconds
  #    and skipping the ~60-90s cold boot. Wait briefly for that; if it stays stopped
  #    (off-state snapshot), start it explicitly. (Calling start on an already-running
  #    VM returns 409 and would abort the run.)
  running=""
  for _ in 1 2 3 4 5 6 7 8; do
    [ "$(get_proxmox_vm_state "$vmid" 2>/dev/null)" = "running" ] && { running=1; break; }
    sleep 1
  done
  if [ -z "$running" ]; then
    upid="$(pve_post "/nodes/${PROXMOX_NODE}/qemu/${vmid}/status/start" | jq -r '.data // empty')"
    wait_for_task "$upid" || { echo "ERR ${name}: start failed" >&2; return 1; }
  fi

  # 3. Wait for the guest agent (near-instant after a vmstate restore).
  wait_for_agent "$vmid" || { echo "ERR ${name}: agent not up" >&2; return 1; }

  # 4. Generate a JIT config (orchestrator holds the PAT; the runner never sees it).
  jitconfig="$(generate_jitconfig "$GITHUB_OWNER" "$GITHUB_REPO" "$REGISTRATION_SCOPE" "$name" "$labels")"
  if [ -z "$jitconfig" ] || [ "$jitconfig" = "null" ]; then
    echo "ERR ${name}: jitconfig generation failed" >&2; return 1
  fi

  # 5. Inject the JIT config via the guest agent (OS-specific path + format).
  if [ "$os" = "windows" ]; then
    env_path='C:\gha-runner\runner.env.ps1'
    env_content="\$env:RUNNER_JITCONFIG='${jitconfig}'"
  else
    env_path='/etc/gha-runner/env'
    env_content="RUNNER_JITCONFIG=${jitconfig}"
  fi
  pve_agent_write_file "$vmid" "$env_path" "$env_content" \
    || { echo "ERR ${name}: jitconfig injection failed" >&2; return 1; }

  echo "${name}: clean, started, JIT config injected — waiter will run one job."
  unset jitconfig env_content
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
