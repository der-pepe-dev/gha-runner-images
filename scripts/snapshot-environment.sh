#!/usr/bin/env bash
# Snapshot the local IaC management-host environment into docs/environment.md.
# Run once per management machine so agents know which tools are available.
#
# Usage: scripts/snapshot-environment.sh
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="docs/environment.md"

emit() { printf '%s\n' "$1" >>"$OUT"; }

version() {
  local cmd="$1"; shift
  if command -v "$cmd" &>/dev/null; then
    local v
    v="$("$cmd" "$@" 2>/dev/null | tr -d '\000\r' | head -1 || true)"
    emit "- \`$cmd\` — ${v:-installed}"
  fi
}

mkdir -p "$(dirname "$OUT")"
: >"$OUT"
emit "# Environment snapshot"
emit ""
emit "_Generated: $(date '+%Y-%m-%d %H:%M') on \`$(uname -n)\` — regenerate with \`scripts/snapshot-environment.sh\`._"
emit ""
emit "> Per-machine management-host snapshot. This repo builds Proxmox-hosted GitHub"
emit "> Actions runner images; the tools below are what the management host has for"
emit "> Packer/Ansible workflows. Agents: prefer tools listed here."
emit ""

emit "## Host"
emit "- Distro: $(lsb_release -ds 2>/dev/null || echo unknown)"
emit "- Kernel: $(uname -r)"
if command -v wsl.exe &>/dev/null; then
  wsl_ver="$(wsl.exe --version 2>/dev/null | tr -d '\000\r' | head -1)"
  emit "- WSL: ${wsl_ver:-interop available}"
fi
emit ""

emit "## Image build / provisioning"
version packer version
version ansible --version
version ansible-lint --version
version ansible-playbook --version
version ansible-vault --version
emit ""

emit "## Cloud / virtualization tooling"
version qm --version          # Proxmox VE CLI (if running on the PVE host)
version pvesh --version       # Proxmox API shell
version virt-customize --version
emit ""

emit "## General CLI"
version git --version
version gh --version
version pwsh --version
version jq --version
version yq --version
version rg --version
emit ""

emit "## Validation shortcuts"
emit "- Packer: \`packer validate <file>.pkr.hcl\` (and \`packer fmt -check\`)."
emit "- Ansible: \`ansible-lint\` and \`ansible-playbook --syntax-check <playbook>.yml\`."
emit "- Never run register-runner playbooks against the golden template — clones only."
emit ""
