#!/usr/bin/env bash
# Provision the local runner orchestrator on THIS host — a tiny Debian/Ubuntu LXC (or a
# node) that reconciles one Proxmox node's runner slots on a systemd timer. Run as root.
#
# It installs deps (curl, jq), the orchestrator + eval-age scripts, the config, an empty
# secrets EnvironmentFile, and enables the systemd timer(s). Copy this orchestrator/
# directory onto the host first (git clone or scp), then: sudo ./install-orchestrator.sh
#
# After running, fill:
#   /etc/gha-local-orchestrator/env          PROXMOX_TOKEN_ID / PROXMOX_TOKEN / GITHUB_TOKEN
#   /etc/gha-local-orchestrator/node.local.env   this node's PROXMOX_URL/NODE + SLOT_* vars
set -euo pipefail

[ "$(id -u)" = "0" ] || { echo "run as root" >&2; exit 1; }
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP=/opt/gha-local-orchestrator
CFG=/etc/gha-local-orchestrator

echo "== installing dependencies (curl, jq) =="
if command -v apt-get >/dev/null; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl jq ca-certificates
else
  echo "apt-get not found — install curl + jq manually" >&2
fi

echo "== installing scripts to ${APP} =="
install -d "$APP" "$CFG"
install -m 0755 "$SD/gha-local-orchestrator.sh" "$APP/gha-local-orchestrator.sh"
install -m 0755 "$SD/gha-orch-trigger.sh" "$APP/gha-orch-trigger.sh"
[ -f "$SD/check-windows-template-age.sh" ] && install -m 0755 "$SD/check-windows-template-age.sh" "$APP/"

echo "== config ${CFG}/node.local.env =="
if [ ! -f "$CFG/node.local.env" ]; then
  if [ -f "$SD/node.local.env" ]; then
    install -m 0644 "$SD/node.local.env" "$CFG/node.local.env"
  else
    install -m 0644 "$SD/node01.example.env" "$CFG/node.local.env"
    echo "  -> copied the example; EDIT $CFG/node.local.env for this node's slots"
  fi
else
  echo "  -> kept existing $CFG/node.local.env"
fi

echo "== secrets ${CFG}/env =="
if [ ! -f "$CFG/env" ]; then
  cat > "$CFG/env" <<'EOF'
# systemd EnvironmentFile — orchestrator secrets. chmod 600. Never commit.
PROXMOX_TOKEN_ID=
PROXMOX_TOKEN=
GITHUB_TOKEN=
EOF
  chmod 600 "$CFG/env"
  echo "  -> created $CFG/env (chmod 600) — FILL the three secrets"
else
  echo "  -> kept existing $CFG/env"
fi

echo "== systemd units =="
install -m 0644 "$SD/gha-local-orchestrator.service" /etc/systemd/system/
install -m 0644 "$SD/gha-local-orchestrator.timer"   /etc/systemd/system/
install -m 0644 "$SD/gha-orch-trigger.service" /etc/systemd/system/
install -m 0644 "$SD/gha-orch-trigger.socket"  /etc/systemd/system/
for u in gha-template-age-check.service gha-template-age-check.timer; do
  [ -f "$SD/$u" ] && install -m 0644 "$SD/$u" /etc/systemd/system/
done
systemctl daemon-reload
systemctl enable --now gha-local-orchestrator.timer
# LAN self-trigger socket (a finished runner pokes it for an immediate reset).
systemctl enable --now gha-orch-trigger.socket
if [ -f /etc/systemd/system/gha-template-age-check.timer ]; then
  systemctl enable --now gha-template-age-check.timer
fi

echo
echo "Installed. The reconcile timer runs every ~2 min (see gha-local-orchestrator.timer)."
echo "Fill $CFG/env + $CFG/node.local.env, then:  systemctl start gha-local-orchestrator.service"
echo "Logs:  journalctl -u gha-local-orchestrator.service -f"
