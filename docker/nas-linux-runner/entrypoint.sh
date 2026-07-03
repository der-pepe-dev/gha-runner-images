#!/usr/bin/env bash
# JIT loop for the NAS Linux GPU runner (TrueNAS Docker app).
# Mints a just-in-time runner config, runs ONE job, then loops with a fresh registration.
# The container filesystem is the ephemeral boundary (the runner also wipes _work per job).
# The PAT stays in the container's secret env — it never reaches a workflow (JIT only).
set -uo pipefail

: "${GITHUB_OWNER:?set GITHUB_OWNER}"
: "${GITHUB_TOKEN:?set GITHUB_TOKEN (fine-grained org PAT: self-hosted-runners RW)}"
NAME="${RUNNER_NAME:-gha-nas-linux-$(hostname)}"
LABELS="${RUNNER_LABELS:-self-hosted,linux,x64,dotnet10,nas,gpu}"
API="https://api.github.com/orgs/${GITHUB_OWNER}/actions/runners"
GH=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

del_stale() {  # a prior JIT config that never connected lingers offline and 409s a new one
  local id
  id="$(curl -fsS "${GH[@]}" "${API}?per_page=100" 2>/dev/null | jq -r --arg n "$NAME" 'first(.runners[]|select(.name==$n)|.id) // empty')"
  if [ -n "$id" ]; then curl -fsS -X DELETE "${GH[@]}" "${API}/${id}" >/dev/null 2>&1 || true; fi
}
gen_jit() {
  local lj body
  lj="$(printf '%s' "$LABELS" | jq -R 'split(",")')"
  body="$(jq -n --arg n "$NAME" --argjson l "$lj" '{name:$n, runner_group_id:1, labels:$l, work_folder:"_work"}')"
  curl -fsS -X POST "${API}/generate-jitconfig" "${GH[@]}" -d "$body" | jq -r '.encoded_jit_config // empty'
}

term=0; trap 'term=1' TERM INT
cd /opt/actions-runner || exit 1
echo "NAS linux runner loop: name=${NAME} labels=${LABELS}"
nvidia-smi -L 2>/dev/null | head -1 || echo "(no GPU visible — check the app's GPU allocation)"

while [ "$term" -eq 0 ]; do
  del_stale
  jit="$(gen_jit)"
  if [ -z "$jit" ]; then echo "jitconfig generation failed; retry in 10s"; sleep 10; continue; fi
  ./run.sh --jitconfig "$jit" || echo "run.sh exited $?"
  [ "$term" -eq 0 ] && sleep 2
done
echo "terminating"; del_stale
