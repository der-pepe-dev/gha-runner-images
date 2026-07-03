# NAS / Beefy Runner Group

The default Proxmox fleet is intentionally lightweight: one Linux runner and one Windows runner per Proxmox node. A NAS or larger server can be added as a separate high-capacity runner group for jobs that need more CPU, memory, disk, or specialized tooling.

## Recommended role

Use the NAS runners for heavier or less frequent jobs:

- release packaging
- larger test matrices
- long-running integration tests
- emulator benchmark jobs
- artifact generation
- Windows Build Tools jobs, if the NAS can host a Windows VM
- jobs needing large local caches or fast local storage

Keep normal PR/build jobs on the lightweight Proxmox runners where possible.

## Suggested naming

```text
nas01:
  gha-nas-linux01
  gha-nas-win01       # optional, only if Windows is useful there
  gha-nas-build01     # optional, for very heavy jobs
```

Use names that describe capacity and placement, not a specific project.

## Label strategy

Keep labels project-neutral. Add a capacity/location label so workflows can opt into the beefier machine only when needed.

Linux NAS runner example:

```text
self-hosted,linux,x64,dotnet10,nas,beefy,ephemeral
```

Windows NAS runner example:

```text
self-hosted,windows,x64,dotnet10,nas,beefy,vs-buildtools,ephemeral
```

Generic lightweight jobs should not include `nas` or `beefy`:

```yaml
runs-on: [self-hosted, linux, x64, dotnet10]
```

Heavy jobs can opt in:

```yaml
runs-on: [self-hosted, linux, x64, dotnet10, beefy]
```

Windows Build Tools jobs can opt in separately:

```yaml
runs-on: [self-hosted, windows, x64, dotnet10, vs-buildtools]
```

## GitHub runner groups

If these runners are registered at organization scope, put them in a separate GitHub runner group such as `beefy` or `nas-beefy`. Runner groups are useful for access control: GitHub describes runner groups as a way to collect runners and create a security boundary around them, and organization-level runners can be made available to multiple repositories. Keep repository access restricted to repos that should be allowed to use the high-capacity server.

## Orchestration model

Prefer a local orchestrator on the NAS/server itself if it can manage its local runner VMs or containers.

```text
nas01:
  gha-nas-orch01 manages gha-nas-linux01 and optional gha-nas-win01
```

If the NAS is not running Proxmox, adapt the same slot model to the platform available there:

- VM snapshot rollback
- container recreate
- direct ephemeral runner service with workspace wipe

VM or container reset is preferred over a long-lived dirty runner.

## Scheduling policy

Do not over-route normal jobs to the NAS. The default labels should keep normal jobs spread across the lightweight Proxmox fleet. Use `beefy`, `nas`, or `vs-buildtools` labels only when the workflow actually needs them.

## Implementation

- **Linux beefy (GPU)** — `docker/nas-linux-runner/`: a TrueNAS Scale 25.10 (Goldeye)
  Docker app. Runs as a container so it **shares the GPU** with your other apps (a VM
  would need exclusive passthrough). CUDA-devel base + the full CI toolchain + a JIT loop
  (mint config → one job → repeat). Labels `nas,beefy,gpu`. See its README to deploy.
- **Windows beefy** — deferred; would be an Incus VM (TrueNAS 25.10 uses Incus for VMs),
  without GPU (Windows can't share it). Port of the Proxmox windows image + JIT loop.
