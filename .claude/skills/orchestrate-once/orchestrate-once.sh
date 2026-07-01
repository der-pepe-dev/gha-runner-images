#!/usr/bin/env bash
# Run one orchestrator reconcile pass from here (rollback -> inject token -> start
# for any stopped slot), to drive/observe the ephemeral loop before the LXC exists.
#
# Creds from the shared gitignored env (../pve-status/pve.local.env):
#   PROXMOX_TOKEN_ID / PROXMOX_TOKEN   GITHUB_TOKEN (org PAT)
#
# Usage:
#   orchestrate-once.sh <path-to-node.local.env>
#   (config sets PROXMOX_URL/NODE, GITHUB_OWNER/REPO, REGISTRATION_SCOPE, SLOT_* vars)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# set -a so the sourced creds are EXPORTED — the orchestrator is exec'd as a fresh
# process and only inherits exported vars.
set -a
# shellcheck source=/dev/null
[ -f "$REPO/.claude/skills/pve-status/pve.local.env" ] && source "$REPO/.claude/skills/pve-status/pve.local.env"
set +a
: "${PROXMOX_TOKEN_ID:?}"; : "${PROXMOX_TOKEN:?}"; : "${GITHUB_TOKEN:?Set GITHUB_TOKEN (org PAT)}"

cfg="${1:?path to a node.local.env config}"
[ -f "$cfg" ] || { echo "config not found: $cfg" >&2; exit 1; }
exec "$REPO/orchestrator/gha-local-orchestrator.sh" "$cfg"
