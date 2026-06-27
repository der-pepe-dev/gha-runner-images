# Runner architecture

The image/runner model for this repo. Read when touching the Packer→Ansible flow or
runner registration. Full operational detail lives in the README and the per-OS docs.

## Purpose

Build reproducible Proxmox-hosted GitHub Actions self-hosted runner images for
home-lab/private CI — primarily Windows and Linux VMs. These runners are what the CI
in the C# projects (DePam, ArtifactView, DedupSharp, ReMedia, FileAudit) runs on.

## Two-stage model

### 1. Packer builds golden templates (`packer/`)
Clean VM templates from installation media: Windows Server Core from ISO +
`autounattend.xml`; Linux from ISO/cloud-init. Base OS config, WinRM/SSH readiness,
guest agent, cleanup. No GitHub runner registration in the image.

### 2. Ansible provisions + registers clones (`ansible/`)
Installs CI tooling (Git, PowerShell 7, .NET 10 SDK, optional VS Build Tools) and
registers CLONED VMs as runners. Registration runs only on clones, never the template.


## Fleet model (local orchestrator per node)

The runner fleet is small and non-HA: each Proxmox node runs a tiny local orchestrator
(LXC) that manages only that node's runner slots. See [[runner-fleet]] for the full
layout and [[nas-runner-group]] for the optional high-capacity pool.

- One orchestrator per node (`gha-orch01` → `pve01`, etc.); failure domains stay simple.
- Runners are **ephemeral**: register with `--ephemeral`, run one job, shut down; the
  orchestrator rolls back a clean snapshot or recreates from template, then re-registers
  with a fresh token. Bootstrap scripts in `orchestrator/bootstrap/`.
- The orchestrator is **bash** (`curl` + `jq` only) on a minimal Debian/Ubuntu LXC,
  run **unprivileged** (it holds Proxmox + GitHub tokens). Per-node config is a flat
  `.env` file (no YAML parser). The Windows runner bootstrap stays PowerShell (it runs
  on Windows). See `orchestrator/README.md`.
- Labels are generic + a node label; project-specific labels are NOT baked in by default
  (these runners are shared across repos). Opt-in labels (`nas`, `beefy`, `vs-buildtools`)
  target the heavier NAS pool only.
- The orchestrator never stores long-lived tokens and never manages other nodes.

## Planned images

- `win-gha-core` — Windows Server Core: Git, PowerShell 7, .NET 10 SDK
- `win-gha-buildtools` — Windows + Visual Studio Build Tools/MSBuild
- `ubuntu-gha-core` — lightweight Linux runner for general CI and .NET builds

## Runner labels

Use explicit labels in workflows, not `windows-latest` / `ubuntu-latest`:

- `[self-hosted, windows, x64, dotnet10, <project>]`
- `[self-hosted, windows, x64, dotnet10, vs-buildtools]` (heavier build-tools runner)
- `[self-hosted, linux, x64, dotnet10]`

## Hard rules (see agent-rules for the full list)

- Never register a runner on the golden template — clones only.
- Registration tokens are short-lived; request at registration time, never bake in.
- Never commit secrets/tokens/passwords/real inventory; `.example.*` files only.
