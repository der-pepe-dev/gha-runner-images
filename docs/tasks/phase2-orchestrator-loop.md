# Task: Phase 2 — orchestrator snapshot-rollback loop (Option A)

Implements the self-sustaining ephemeral runner loop per
[[decisions/0001-self-sustaining-fleet]] using guest-agent token injection (Option A).

## Done

- [x] `reset_runner_slot` in `gha-local-orchestrator.sh`: rollback to clean snapshot →
      start → wait for guest agent → mint fresh org token → write the runner env into the
      guest via `agent/file-write` (OS-specific path/format). Helpers: `pve_post`,
      `wait_for_task`, `wait_for_agent`, `pve_agent_write_file`. shellcheck clean.
- [x] Linux waiter unit `bootstrap/gha-runner-waiter.service` — waits for
      `/etc/gha-runner/env`, then runs `linux-runner-once.sh` (register --ephemeral, one
      job, shutdown).

## Remaining (needs a template rebuild)

- [x] **Bake the runner into the Linux template** (Packer): create the `gha-runner` user,
      download + extract the actions-runner package to `/opt/actions-runner` (config.sh
      present, NOT registered), install `linux-runner-once.sh` to `/opt/gha-runner/`,
      install + enable `gha-runner-waiter.service`. Keep the runner UNREGISTERED in the
      image.
- [ ] **Windows waiter**: a boot scheduled task that waits for
      `C:\gha-runner\runner.env.ps1` then runs `windows-runner-once.ps1`; bake the runner
      package + bootstrap into the Windows template.
- [ ] **Per-slot one-time setup**: clone the template to the slot VMID, boot to the
      ready/unregistered state, take the `clean` snapshot (the orchestrator's
      `SLOT_<n>_CLEAN_SNAPSHOT`, default `clean`). A small setup script/playbook.
- [ ] **Wire the orchestrator on a node**: deploy the script + `node.local.env` + the
      systemd service/timer; secrets via EnvironmentFile (PROXMOX_TOKEN_ID/TOKEN,
      GITHUB_TOKEN). Test one full cycle: job runs → VM shuts down → orchestrator rolls
      back + re-injects → clean runner returns.

## Notes

- The orchestrator never registers via Ansible in this loop — it mints the token (PAT)
  and the in-VM waiter+bootstrap registers `--ephemeral`. Ansible registration (Phase 1)
  remains the path for persistent/manual runners.
- linux-runner-once.sh already sources `/etc/gha-runner/env`, registers `--ephemeral`,
  runs `./run.sh`, and shuts down — the waiter just blocks until the env exists.
