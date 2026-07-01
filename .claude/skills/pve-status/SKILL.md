---
name: pve-status
description: Read-only Proxmox VE status for the GHA runner fleet — cluster overview, VM/template state, snapshots, and guest-agent IP. Use when the user asks about Proxmox/PVE status, whether a VM/template/snapshot exists, a runner slot's state, or the agent/IP of a VM. Read-only (no VM changes).
---

# PVE status

Quick read-only checks against the Proxmox API, using the same env token as the
orchestrator and `discover-proxmox.sh`. No changes are made to any VM.

## Prereqs (env)

```
PROXMOX_URL       https://<node>:8006/api2/json
PROXMOX_TOKEN_ID  packer@pve!packer
PROXMOX_TOKEN     <secret>
```
If unset, ask the user to export them (same values used for discovery/builds). Self-signed
certs are accepted (`-k`).

## Commands

```bash
S=.claude/skills/pve-status/pve-status.sh
bash "$S"                 # cluster overview: nodes + every VM/template
bash "$S" templates       # just templates (find the gha template VMIDs)
bash "$S" vm <vmid>       # one VM: status, cpu/scsihw/net, agent IP, snapshots
bash "$S" snapshots <vmid># snapshot list (e.g. confirm the 'clean' slot snapshot)
bash "$S" agent <vmid>    # guest-agent ping + IPv4
```

## When to use

- Confirm a template exists / its VMID (before cloning a slot).
- Check a runner slot's state (`stopped` = job done / ready to reset; `running` = busy).
- Confirm the `clean` snapshot exists before the orchestrator rolls back to it.
- Get a VM's IP (for the Ansible inventory) via the guest agent.
- Sanity-check hardware (virtio-scsi, virtio NIC, host CPU) on a built template.

Run the relevant command, then summarize the result for the user — don't dump raw JSON.
