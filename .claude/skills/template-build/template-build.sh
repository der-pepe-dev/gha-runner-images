#!/usr/bin/env bash
# Build a golden template with Packer, from the right dir with the token wired in.
# Long-running — the SKILL tells the agent to run it in the background.
#
# Proxmox token from the shared gitignored env (../pve-status/pve.local.env):
#   PROXMOX_TOKEN  (build-privileged: PVEVMAdmin + PVEDatastoreAdmin + PVESDNUser)
# The per-OS local.pkrvars.hcl (written by discover-proxmox.sh) supplies the rest.
#
# Usage:
#   template-build.sh <linux|windows|buildtools> [extra packer args...]
#   e.g. template-build.sh linux -var install_updates=false
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=/dev/null
[ -f "$REPO/.claude/skills/pve-status/pve.local.env" ] && source "$REPO/.claude/skills/pve-status/pve.local.env"
: "${PROXMOX_TOKEN:?Set PROXMOX_TOKEN (build-privileged)}"

kind="${1:?linux|windows|buildtools}"; shift || true
case "$kind" in
  linux)      dir="$REPO/packer/linux";   tmpl="ubuntu-gha-core.pkr.hcl" ;;
  windows)    dir="$REPO/packer/windows"; tmpl="windows-gha-core.pkr.hcl" ;;
  buildtools) dir="$REPO/packer/windows"; tmpl="windows-gha-buildtools.pkr.hcl" ;;
  *) echo "kind must be linux|windows|buildtools" >&2; exit 2 ;;
esac

cd "$dir"
[ -f local.pkrvars.hcl ] || { echo "missing $dir/local.pkrvars.hcl — run discover-proxmox.sh first" >&2; exit 1; }
packer init "$tmpl" >/dev/null
exec packer build -var-file=local.pkrvars.hcl -var "proxmox_token=${PROXMOX_TOKEN}" "$@" "$tmpl"
