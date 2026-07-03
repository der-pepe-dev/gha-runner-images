---
name: runner-reseed
description: Safely (re)seed a runner slot from a golden template with a clean vmstate snapshot. Pauses the node's timer+trigger socket so the snapshot can't capture a registered runner. Use after a template rebuild or to fix a stuck/bad slot.
---

# runner-reseed

Re-seeds one runner slot from a golden template and takes a **clean vmstate (RAM)
snapshot** — the state a slot rolls back to for every job. Replaces the fragile manual
patch+resnap that once corrupted the linux slots (a reconcile fired mid-snapshot and froze
a registered runner → stuck offline).

## What it guarantees

1. Pauses the node's `gha-local-orchestrator.timer` **and** `gha-orch-trigger.socket`
   (a reconcile/poke mid-snapshot is the corruption cause) — and always resumes (trap).
2. Clones **fresh from the template** → clean-waiting by construction (no leftover runner).
3. Windows: renames the VM to the runner name (`Rename-Computer -Restart`); Linux self-names
   per boot via the bootstrap.
4. Snapshots `clean` **with RAM state** (fast-path rollback).

## Setup

`cp reseed.local.env.example reseed.local.env` and fill the orchestrator SSH key + the
node→orchestrator-LXC IP map. Proxmox creds come from `../pve-status/pve.local.env`.

## Usage

```bash
bash .claude/skills/runner-reseed/runner-reseed.sh <node> <vmid> <name> <template_vmid> <linux|windows>
# linux slot from template 107:
bash .claude/skills/runner-reseed/runner-reseed.sh pve2 312 gha-linux-eph02 107 linux
# windows slot from template 106:
bash .claude/skills/runner-reseed/runner-reseed.sh pve1 321 gha-win-eph01 106 windows
```

Run it once per slot after a template rebuild. The slot's orchestrator then cycles the new
clean snapshot on its timer.

## Notes

- Windows rename lives only in that slot's snapshot — always re-run this skill on a Windows
  re-seed (linux is automatic). See docs/tasks/lessons.md.
- Full clones on Ceph are cross-node capable (`target=<node>`).
