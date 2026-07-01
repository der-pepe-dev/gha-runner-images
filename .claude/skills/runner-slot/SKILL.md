---
name: runner-slot
description: Create or destroy an ephemeral runner slot VM on Proxmox — full-clone a golden template and take the 'clean' unregistered snapshot the orchestrator rolls back to, or purge a slot. Use when setting up / tearing down a runner slot for the snapshot-rollback loop.
---

# runner-slot

Manage the per-slot VM the orchestrator cycles. Creds come from the shared gitignored
`.claude/skills/pve-status/pve.local.env` (PROXMOX_URL/TOKEN_ID/TOKEN, optional
PROXMOX_NODE/PROXMOX_STORAGE).

```bash
S=.claude/skills/runner-slot/runner-slot.sh
bash "$S" create <template_vmid> <slot_vmid> <name> [snapshot=clean]
bash "$S" destroy <slot_vmid>
```

- `create` full-clones the template to the slot VMID, then snapshots it `clean` while
  stopped + unregistered — exactly the state the orchestrator rolls back to each job.
- `destroy` stops and purges the slot VM.

Example (Phase 2 slot from the baked Linux template 108):
`bash "$S" create 108 311 gha-linux-eph01` → then run the orchestrator against a config
whose SLOT points at 311. Confirm with `/pve-status vm 311`.
