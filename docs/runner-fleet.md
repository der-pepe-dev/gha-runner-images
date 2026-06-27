# Runner Fleet Layout

This repository is optimized for a small, non-HA Proxmox runner fleet with local orchestration.

## Default placement

| Proxmox node | Local orchestrator | Linux runner | Windows runner | Role |
|---|---|---|---|---|
| `pve01` | `gha-orch01` | `gha-linux01` | `gha-win01` | General Linux + Windows CI |
| `pve02` | `gha-orch02` | `gha-linux02` | `gha-win02` | General Linux + Windows CI |
| `pve03` | `gha-orch03` | `gha-linux03` | `gha-win03` | General Linux + Windows CI |

The design deliberately avoids HA for runners. Each runner VM lives on a specific Proxmox node. If that node is down, its local orchestrator and its runner labels are unavailable until the node returns.

## Local orchestrator model

Each Proxmox node has a tiny local orchestrator, usually a small Debian/Ubuntu LXC, that manages only the two runner slots on that node.

```text
pve01:
  gha-orch01 manages gha-linux01 and gha-win01

pve02:
  gha-orch02 manages gha-linux02 and gha-win02

pve03:
  gha-orch03 manages gha-linux03 and gha-win03
```

This avoids a single central controller and avoids requiring Proxmox HA for the orchestrator. If `pve02` is offline, there is no useful work for `gha-orch02` to do elsewhere because `gha-linux02` and `gha-win02` are intentionally pinned to `pve02`.

## Label strategy

Every runner should have generic labels plus a node label. Do not include project-specific labels by default; these runners are intended to be reusable by multiple repositories in the same organization.

Linux example:

```text
self-hosted,linux,x64,dotnet10,proxmox,pve01,ephemeral
```

Windows example:

```text
self-hosted,windows,x64,dotnet10,proxmox,pve01,ephemeral
```

Use generic labels for normal jobs:

```yaml
runs-on: [self-hosted, linux, x64, dotnet10]
```

Use the node label only when a job must run on a specific Proxmox node:

```yaml
runs-on: [self-hosted, windows, x64, dotnet10, pve02]
```

## Suggested VM sizing

| Runner type | vCPU | RAM | Disk | Notes |
|---|---:|---:|---:|---|
| Local orchestrator LXC | 1 | 512 MB-1 GB | 4-8 GB | Runs local reconcile timer/script |
| Linux lightweight | 2-4 | 4-8 GB | 40-80 GB | Good for .NET, scripts, packaging |
| Windows lightweight | 4 | 8 GB | 80 GB | Server Core + .NET SDK |
| Windows Build Tools | 6 | 12-16 GB | 128 GB | Optional only; heavier image |

## Operational model

- Keep work directories local to each VM.
- Avoid shared disks for runner workspaces.
- Do not enable Proxmox HA for runner VMs by default.
- Use one local orchestrator per Proxmox node.
- Treat runners as disposable: rebuild from template or roll back a clean snapshot after each ephemeral job.
- Keep runner registration out of the golden template.
- Clone from template, configure hostname/IP, then run the registration/bootstrap step with a fresh token.

## Naming convention

```text
gha-orch01  -> pve01
gha-orch02  -> pve02
gha-orch03  -> pve03

gha-linux01 -> pve01
gha-linux02 -> pve02
gha-linux03 -> pve03

gha-win01   -> pve01
gha-win02   -> pve02
gha-win03   -> pve03
```

The host number maps to the Proxmox node number.

## Optional NAS / beefy capacity

A NAS or larger server can be added as a separate capacity pool without changing the lightweight 3-node Proxmox layout.

```text
nas01:
  gha-nas-orch01
  gha-nas-linux01
  gha-nas-win01      # optional
```

Do not make normal jobs depend on the NAS. Add opt-in labels such as `nas`, `beefy`, and `vs-buildtools` only to jobs that need the larger machine.

Example NAS labels:

```text
self-hosted,linux,x64,dotnet10,nas,beefy,ephemeral
self-hosted,windows,x64,dotnet10,nas,beefy,vs-buildtools,ephemeral
```

See `docs/nas-runner-group.md` for the detailed model.
