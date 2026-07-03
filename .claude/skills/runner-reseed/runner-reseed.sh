#!/usr/bin/env bash
# Safely (re)seed one runner slot from a golden template with a CLEAN vmstate snapshot.
#
# Codifies the hard-won procedure (see docs/tasks/lessons.md). The failure this prevents:
# if the orchestrator timer OR the LAN trigger socket fires during snapshotting, it injects
# a JIT config -> the waiter runs a real runner -> the vmstate snapshot freezes a REGISTERED
# runner with a soon-stale session. On rollback it resumes offline and never shuts down, so
# the orchestrator (resets only 'stopped' slots) skips it -> the slot is stuck offline.
#
# This script always: pauses the node's timer + trigger socket, clones fresh from the
# template (a fresh clone is clean-waiting by construction), boots, renames Windows to the
# runner name (linux self-names per boot via the bootstrap), snapshots WITH RAM state, then
# resumes. No manual patch+resnap.
#
# Usage: runner-reseed.sh <node> <vmid> <name> <template_vmid> <linux|windows>
#   e.g. runner-reseed.sh pve1 321 gha-win-eph01 106 windows
set -euo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SD/../pve-status/pve.local.env"          # PROXMOX_URL / PROXMOX_TOKEN_ID / PROXMOX_TOKEN
# shellcheck source=/dev/null
source "$SD/reseed.local.env"                     # ORCH_SSH_KEY + ORCH_IP_<node> map

[ "$#" -eq 5 ] || { echo "usage: runner-reseed.sh <node> <vmid> <name> <template_vmid> <linux|windows>" >&2; exit 1; }
node="$1"; vmid="$2"; name="$3"; tmpl="$4"; os="$5"
STORAGE="${RESEED_STORAGE:-OsdPool}"
AUTH="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN}"

api() { curl -fsS -k -H "$AUTH" "$@"; }
wtask() { local n="$1" u="$2" b; [ -n "$u" ] && [ "$u" != "null" ] || return 0
  while b=$(api "${PROXMOX_URL}/nodes/$n/tasks/${u}/status" 2>/dev/null); [ "$(jq -r .data.status <<<"$b")" != "stopped" ]; do sleep 4; done
  [ "$(jq -r .data.exitstatus <<<"$b")" = "OK" ]; }
state() { api "${PROXMOX_URL}/nodes/$node/qemu/$vmid/status/current" 2>/dev/null | jq -r '.data.status // "?"'; }
wait_agent() { for _ in $(seq 1 100); do api -X POST "${PROXMOX_URL}/nodes/$node/qemu/$vmid/agent/ping" >/dev/null 2>&1 && return 0; sleep 3; done; return 1; }

# Orchestrator LXCs use DHCP, so resolve the current IP from the stable LXC VMID at runtime
# (node->orch-LXC-VMID map in reseed.local.env). Falls back to a static ORCH_IP_<node> if set.
orch_vmid_var="ORCH_VMID_${node}"; orch_vmid="${!orch_vmid_var:-}"
orch_ip_var="ORCH_IP_${node}"; orch_ip="${!orch_ip_var:-}"
if [ -z "$orch_ip" ] && [ -n "$orch_vmid" ]; then
  orch_ip="$(api "${PROXMOX_URL}/nodes/${node}/lxc/${orch_vmid}/interfaces" 2>/dev/null \
    | jq -r '.data[]?|select(.name=="eth0")|.inet // empty' | cut -d/ -f1 | head -1)"
  [ -n "$orch_ip" ] && echo "resolved ${node} orchestrator LXC ${orch_vmid} -> ${orch_ip}"
fi
ssh_orch() { ssh -i "$ORCH_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 "root@${orch_ip}" "$@"; }

pause_orch() {
  if [ -n "$orch_ip" ]; then
    ssh_orch 'systemctl stop gha-local-orchestrator.timer gha-orch-trigger.socket' && echo "paused ${node} orchestrator (timer+socket)"
  else
    echo "WARN: no ORCH_IP_${node} in reseed.local.env — cannot pause the timer/socket; a" >&2
    echo "      concurrent reconcile could corrupt this snapshot. Set it, or pause manually." >&2
  fi
}
resume_orch() { [ -n "$orch_ip" ] && ssh_orch 'systemctl start gha-local-orchestrator.timer gha-orch-trigger.socket' && echo "resumed ${node} orchestrator"; }
trap resume_orch EXIT   # always resume, even on error

pause_orch

echo "== destroy old slot ${vmid} (if present) =="
if api "${PROXMOX_URL}/nodes/$node/qemu/$vmid/status/current" >/dev/null 2>&1; then
  api -X POST "${PROXMOX_URL}/nodes/$node/qemu/$vmid/status/stop" >/dev/null 2>&1 || true
  until [ "$(state)" = "stopped" ] || [ "$(state)" = "?" ]; do sleep 3; done
  u=$(api -X DELETE "${PROXMOX_URL}/nodes/$node/qemu/$vmid?purge=1&destroy-unreferenced-disks=1" | jq -r '.data // empty'); wtask "$node" "$u"
fi

echo "== clone template ${tmpl} -> ${vmid} (${name}) on ${node} =="
# The clone must be issued to the node where the template lives (then target=$node).
tmpl_node="$(api "${PROXMOX_URL}/cluster/resources?type=vm" | jq -r --argjson t "$tmpl" '.data[]|select(.vmid==$t and .template==1)|.node' | head -1)"
[ -n "$tmpl_node" ] || { echo "template ${tmpl} not found in cluster" >&2; exit 1; }
u=$(api -X POST "${PROXMOX_URL}/nodes/${tmpl_node}/qemu/${tmpl}/clone" \
  --data-urlencode "newid=${vmid}" --data-urlencode "name=${name}" \
  --data-urlencode "target=${node}" --data-urlencode "full=1" --data-urlencode "storage=${STORAGE}" | jq -r '.data // empty')
wtask "$tmpl_node" "$u" || { echo "clone failed" >&2; exit 1; }

echo "== boot + wait for agent =="
u=$(api -X POST "${PROXMOX_URL}/nodes/$node/qemu/$vmid/status/start" | jq -r '.data // empty'); wtask "$node" "$u" || true
wait_agent || { echo "agent did not come up" >&2; exit 1; }

if [ "$os" = "windows" ]; then
  echo "== rename Windows -> ${name} (+reboot) =="
  api -X POST "${PROXMOX_URL}/nodes/$node/qemu/$vmid/agent/exec" \
    --data-urlencode "command=powershell.exe" --data-urlencode "command=-Command" \
    --data-urlencode "command=Rename-Computer -NewName ${name} -Force -Restart" >/dev/null 2>&1 || true
  sleep 20; wait_agent || { echo "agent did not return after rename reboot" >&2; exit 1; }
fi

echo "== settle (waiter task polling) =="
sleep 25

echo "== snapshot 'clean' WITH RAM state =="
# Replace any existing clean snapshot.
if api "${PROXMOX_URL}/nodes/$node/qemu/$vmid/snapshot/clean/config" >/dev/null 2>&1; then
  u=$(api -X DELETE "${PROXMOX_URL}/nodes/$node/qemu/$vmid/snapshot/clean" | jq -r '.data // empty'); wtask "$node" "$u"
fi
u=$(api -X POST "${PROXMOX_URL}/nodes/$node/qemu/$vmid/snapshot" --data-urlencode "snapname=clean" --data-urlencode "vmstate=1" | jq -r '.data // empty')
wtask "$node" "$u" || { echo "snapshot failed" >&2; exit 1; }
api -X POST "${PROXMOX_URL}/nodes/$node/qemu/$vmid/status/stop" >/dev/null 2>&1 || true

echo "OK: ${vmid} (${name}) re-seeded from ${tmpl} with a clean vmstate snapshot."
