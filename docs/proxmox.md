# Proxmox Notes

The values in this repository are examples only. Adapt storage names, bridges, ISO paths, VM IDs, and node names to your Proxmox VE host.

## Suggested VM sizing

| Template / VM | vCPU | RAM | Disk |
|---|---:|---:|---:|
| Local orchestrator LXC | 1 | 512 MB-1 GB | 4-8 GB |
| Windows core | 4 | 8 GB | 80 GB SSD |
| Windows buildtools | 6 | 12-16 GB | 128 GB SSD |
| Linux core | 2-4 | 4-8 GB | 40-80 GB SSD |

## Recommended VM hardware

- Machine type: `q35` for runner VMs.
- Disk controller: VirtIO SCSI / `virtio-scsi-single`.
- Disk bus: SCSI.
- Network: VirtIO NIC.
- Guest integration: QEMU guest agent.
- Storage: local thin SSD-backed storage if available.

## Notes

Avoid memory hotplug and NUMA unless you need them. They add complexity and can trigger Windows/Proxmox configuration issues. For small CI runners, fixed RAM is usually simpler.

Keep runner VMs isolated from sensitive networks where possible. Treat self-hosted runners as machines that can execute workflow code and access job-scoped secrets.

## Non-HA fleet placement

Default runner placement is one Linux VM and one Windows VM per Proxmox node, with one local orchestrator per node:

| Node | Local orchestrator | Linux VM | Windows VM |
|---|---|---|---|
| `pve01` | `gha-orch01` | `gha-linux01` | `gha-win01` |
| `pve02` | `gha-orch02` | `gha-linux02` | `gha-win02` |
| `pve03` | `gha-orch03` | `gha-linux03` | `gha-win03` |

Do not configure Proxmox HA for these by default. The intended failure mode is simple: when a node is offline, its local orchestrator and its two GitHub runners are offline. GitHub continues scheduling to other online runners that satisfy the requested labels.

Recommended VM settings for each runner:

- VirtIO SCSI controller.
- VirtIO NIC.
- QEMU guest agent enabled.
- Local SSD-backed storage.
- No shared workspace disk.
- Avoid memory hotplug/NUMA unless there is a specific need.

## Local orchestrators

The local orchestrator can be a tiny Debian/Ubuntu LXC on each node. It should manage only that node's runner slots. This keeps failure domains aligned and avoids needing a central HA controller.
