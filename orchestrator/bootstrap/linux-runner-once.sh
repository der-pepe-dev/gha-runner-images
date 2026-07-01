#!/usr/bin/env bash
set -euo pipefail

# One-shot ephemeral GitHub Actions runner bootstrap.
# Intended to run inside a disposable Linux runner VM after the local
# orchestrator injects /etc/gha-runner/env.

ENV_FILE="${GHA_RUNNER_ENV_FILE:-/etc/gha-runner/env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

: "${RUNNER_URL:?RUNNER_URL is required}"
: "${RUNNER_TOKEN:?RUNNER_TOKEN is required}"
: "${RUNNER_NAME:?RUNNER_NAME is required}"
: "${RUNNER_LABELS:?RUNNER_LABELS is required}"

RUNNER_DIR="${RUNNER_DIR:-/opt/actions-runner}"
RUNNER_WORK_DIR="${RUNNER_WORK_DIR:-/opt/actions-work}"
RUNNER_USER="${RUNNER_USER:-gha-runner}"

mkdir -p "$RUNNER_DIR" "$RUNNER_WORK_DIR"
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR" "$RUNNER_WORK_DIR"

cd "$RUNNER_DIR"

if [[ ! -x ./config.sh ]]; then
  echo "config.sh not found in $RUNNER_DIR; bake or extract the runner package before using this script." >&2
  exit 1
fi

cleanup() {
  set +e
  sudo -u "$RUNNER_USER" ./config.sh remove --unattended --token "$RUNNER_TOKEN" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --disableupdate: a baked runner is often older than the server version, and the
# auto-update restart deletes the one-shot --ephemeral registration mid-update
# ("Failed to create a session ... registration has been deleted"). Disable it so the
# ephemeral runner stays registered; keep the baked runner_version reasonably current.
sudo -u "$RUNNER_USER" ./config.sh --unattended --ephemeral --disableupdate --url "$RUNNER_URL" --token "$RUNNER_TOKEN" --name "$RUNNER_NAME" --labels "$RUNNER_LABELS" --work "$RUNNER_WORK_DIR" --replace

sudo -u "$RUNNER_USER" ./run.sh

shutdown -h now
