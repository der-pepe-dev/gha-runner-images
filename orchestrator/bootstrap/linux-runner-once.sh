#!/usr/bin/env bash
set -euo pipefail

# One-shot JIT GitHub Actions runner bootstrap.
# Runs inside a disposable Linux runner VM after the orchestrator injects
# /etc/gha-runner/env with RUNNER_JITCONFIG (a base64 encoded JIT config).
#
# JIT: no config.sh, no registration token, no on-disk credentials. run.sh consumes
# the one-shot config, runs a single job, exits; GitHub auto-removes the runner. Then
# this shuts the VM down and the orchestrator rolls it back for the next job.

ENV_FILE="${GHA_RUNNER_ENV_FILE:-/etc/gha-runner/env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

: "${RUNNER_JITCONFIG:?RUNNER_JITCONFIG is required}"

RUNNER_DIR="${RUNNER_DIR:-/opt/actions-runner}"
RUNNER_USER="${RUNNER_USER:-gha-runner}"

cd "$RUNNER_DIR"
if [[ ! -x ./run.sh ]]; then
  echo "run.sh not found in $RUNNER_DIR; bake the runner package before using this script." >&2
  exit 1
fi

# The injected config is single-use; remove the env file once we've read it so a
# leftover blob can't be read by the job.
rm -f "$ENV_FILE" 2>/dev/null || true

# A vmstate (RAM) snapshot restore leaves the guest clock frozen at snapshot time (can be
# far in the past). A stale clock breaks JIT/token auth — GitHub rejects the runner and it
# exits. Force an immediate NTP resync (timesyncd steps large offsets on restart) before
# starting the runner. Harmless on a cold boot (clock already correct).
timedatectl set-ntp true 2>/dev/null || true
systemctl restart systemd-timesyncd 2>/dev/null || true
for _ in $(seq 1 20); do
  [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ] && break
  sleep 1
done

sudo -u "$RUNNER_USER" ./run.sh --jitconfig "$RUNNER_JITCONFIG"

shutdown -h now
