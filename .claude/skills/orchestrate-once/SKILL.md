---
name: orchestrate-once
description: Run one orchestrator reconcile pass from here (rollback → inject fresh token → start any stopped slot) against a node config, to drive/observe the ephemeral runner loop before the orchestrator LXC is deployed.
---

# orchestrate-once

Runs `orchestrator/gha-local-orchestrator.sh` once against a node config. Creds from the
shared gitignored `.claude/skills/pve-status/pve.local.env`: `PROXMOX_TOKEN_ID`,
`PROXMOX_TOKEN`, `GITHUB_TOKEN` (org PAT).

```bash
bash .claude/skills/orchestrate-once/orchestrate-once.sh <path-to-node.local.env>
```

The config (copy from `orchestrator/node01.example.env`) sets `PROXMOX_URL`/`NODE`,
`GITHUB_OWNER`/`REPO`, `REGISTRATION_SCOPE`, and the `SLOT_*` vars. For each stopped slot
the orchestrator rolls back to `clean`, starts the VM, mints a fresh token, and injects
`/etc/gha-runner/env` via the guest agent; the in-VM waiter registers `--ephemeral`.

Use after `runner-slot create` to test one cycle. Re-run (or loop) to cycle again after
a job finishes and the VM shuts down.
