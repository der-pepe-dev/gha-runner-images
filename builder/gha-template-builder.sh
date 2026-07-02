#!/usr/bin/env bash
# Runs on the builder LXC on a timer: git pull, rebuild the golden template(s) with
# Packer, then retire older same-name templates (keep the newest). No management host.
#
# Secrets from the systemd EnvironmentFile (/etc/gha-builder/env):
#   PROXMOX_TOKEN_ID / PROXMOX_TOKEN   (build-privileged)   GITHUB not needed for builds
# Non-secret config from /etc/gha-builder/build.env:
#   REPO_DIR      checkout of this repo (default /opt/gha-runner-images)
#   PROXMOX_URL   any node's API (default https://127.0.0.1:8006/api2/json)
#   BUILD_KINDS   space list: linux windows buildtools   (default: linux)
set -euo pipefail

REPO_DIR="${REPO_DIR:-/opt/gha-runner-images}"
PROXMOX_URL="${PROXMOX_URL:-https://127.0.0.1:8006/api2/json}"
BUILD_KINDS="${BUILD_KINDS:-linux}"
: "${PROXMOX_TOKEN_ID:?}"; : "${PROXMOX_TOKEN:?}"
AUTH="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN}"

log() { echo "[$(date '+%F %T')] $*"; }
api() { curl -fsS -k -H "$AUTH" "$@"; }

# Delete every template named $1 EXCEPT the newest VMID (the one just built).
retire_old_templates() {
  local name="$1" keep node vmid
  # highest vmid with this name that is a template = the freshest build
  keep="$(api "${PROXMOX_URL}/cluster/resources?type=vm" \
    | jq -r --arg n "$name" '[.[]|select(.template==1 and .name==$n)]|max_by(.vmid)|.vmid // empty')"
  [ -n "$keep" ] || { log "no template named $name found (build failed?)"; return 1; }
  api "${PROXMOX_URL}/cluster/resources?type=vm" \
    | jq -r --arg n "$name" --argjson keep "$keep" '.[]|select(.template==1 and .name==$n and .vmid!=$keep)|"\(.vmid) \(.node)"' \
    | while read -r vmid node; do
        [ -n "$vmid" ] || continue
        log "retiring old template $vmid ($name) on $node"
        api -X DELETE "${PROXMOX_URL}/nodes/${node}/qemu/${vmid}?purge=1&destroy-unreferenced-disks=1" >/dev/null || log "  delete $vmid failed"
      done
  log "current $name template = $keep"
}

# Latest stable actions/runner version, so rebuilds never ship a deprecated runner.
latest_runner() {
  curl -fsS "https://api.github.com/repos/actions/runner/releases?per_page=8" 2>/dev/null \
    | jq -r '[.[]|select(.prerelease==false and .draft==false)|.tag_name][0] // empty' | sed 's/^v//'
}

cd "$REPO_DIR"
log "git pull"
git pull --ff-only || log "git pull failed (using current checkout)"
RV="$(latest_runner || true)"
if [ -n "$RV" ]; then log "latest runner version: $RV"; else log "could not fetch latest runner version (using pinned default)"; fi

# Generate local.pkrvars.hcl from the cluster if absent (first run).
if [ ! -f "$REPO_DIR/packer/linux/local.pkrvars.hcl" ]; then
  log "generating pkrvars via discover-proxmox.sh"
  PROXMOX_URL="$PROXMOX_URL" PROXMOX_TOKEN_ID="$PROXMOX_TOKEN_ID" PROXMOX_TOKEN="$PROXMOX_TOKEN" \
    bash "$REPO_DIR/scripts/discover-proxmox.sh" --force || log "discover failed"
fi

for kind in $BUILD_KINDS; do
  case "$kind" in
    linux)      dir="packer/linux";   tmpl="ubuntu-gha-core.pkr.hcl";     name="tmpl-ubuntu-gha-core" ;;
    windows)    dir="packer/windows";  tmpl="windows-gha-core.pkr.hcl";     name="tmpl-win-gha-core" ;;
    buildtools) dir="packer/windows";  tmpl="windows-gha-buildtools.pkr.hcl"; name="tmpl-win-gha-buildtools" ;;
    *) log "unknown BUILD_KIND: $kind"; continue ;;
  esac
  cd "$REPO_DIR/$dir"
  [ -f local.pkrvars.hcl ] || { log "missing $dir/local.pkrvars.hcl — run discover-proxmox.sh on the builder"; continue; }
  log "building $kind template ..."
  packer init "$tmpl" >/dev/null
  # Linux bakes the runner — pass the latest version if we fetched one.
  rv_arg=()
  [ "$kind" = "linux" ] && [ -n "$RV" ] && rv_arg=(-var "runner_version=${RV}")
  if packer build -var-file=local.pkrvars.hcl -var "proxmox_token=${PROXMOX_TOKEN}" "${rv_arg[@]}" "$tmpl"; then
    log "$kind build OK"
    retire_old_templates "$name" || true
  else
    log "$kind build FAILED — keeping the existing template"
  fi
done
log "done"
