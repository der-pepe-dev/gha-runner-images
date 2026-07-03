#!/usr/bin/env bash
# Single-shot JIT runner for the NAS Linux GPU runner (TrueNAS Docker app).
# Mints a just-in-time runner config, runs ONE job, then exits. The container is set
# `restart: always`, so each job runs in a FRESH container — a pristine filesystem per job
# (cleaner than an in-container loop). The PAT stays in the container's secret env and never
# reaches a workflow (JIT config only).
#
# On a mint failure it sleeps before exiting so `restart: always` (plus Docker's restart
# backoff) doesn't hot-loop on a bad token / no network.
set -uo pipefail

: "${GITHUB_OWNER:?set GITHUB_OWNER}"
: "${GITHUB_TOKEN:?set GITHUB_TOKEN (fine-grained org PAT: self-hosted-runners RW)}"
NAME="${RUNNER_NAME:-gha-nas-linux-$(hostname)}"
LABELS="${RUNNER_LABELS:-self-hosted,linux,x64,dotnet10,nas,gpu,android}"
API="https://api.github.com/orgs/${GITHUB_OWNER}/actions/runners"
GH=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

fail_sleep() { echo "$1" >&2; sleep "${RETRY_DELAY:-10}"; exit 1; }

# A prior JIT config that never connected lingers offline and 409s a new one with this name.
del_stale() {
  local id
  id="$(curl -fsS "${GH[@]}" "${API}?per_page=100" 2>/dev/null | jq -r --arg n "$NAME" 'first(.runners[]|select(.name==$n)|.id) // empty')"
  if [ -n "$id" ]; then curl -fsS -X DELETE "${GH[@]}" "${API}/${id}" >/dev/null 2>&1 || true; fi
}

echo "NAS linux runner: name=${NAME} labels=${LABELS}"
nvidia-smi -L 2>/dev/null | head -1 || echo "(no GPU visible — check the app's GPU allocation)"

del_stale
labels_json="$(printf '%s' "$LABELS" | jq -R 'split(",")')"
body="$(jq -n --arg n "$NAME" --argjson l "$labels_json" '{name:$n, runner_group_id:1, labels:$l, work_folder:"_work"}')"
jit="$(curl -fsS -X POST "${API}/generate-jitconfig" "${GH[@]}" -d "$body" | jq -r '.encoded_jit_config // empty')" \
  || fail_sleep "jitconfig request failed"
[ -n "$jit" ] || fail_sleep "empty jitconfig (check the token scope / org)"

cd /opt/actions-runner || exit 1
# One job, then exit -> restart:always gives the next job a fresh container.
exec ./run.sh --jitconfig "$jit"
