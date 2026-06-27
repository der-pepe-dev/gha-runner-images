# GitHub Actions Self-Hosted Runner Images

Packer and Ansible automation for building Proxmox-hosted GitHub Actions self-hosted runner images.

This repository is intended for reproducible home-lab/private infrastructure runners, especially lightweight Windows and Linux VMs hosted on Proxmox VE.

## Goals

- Build reproducible Windows and Linux runner templates.
- Keep GitHub runner registration out of golden images.
- Support lightweight .NET runners and optional heavier Windows Build Tools runners.
- Run one Linux runner and one Windows runner per Proxmox node.
- Use one local orchestrator per Proxmox node to recreate/reset that node's runners.
- Optionally add a separate NAS/beefy runner group for high-capacity jobs.
- Avoid committing secrets, runner registration tokens, Proxmox tokens, passwords, or real inventory.

## Planned images

| Image | Purpose |
|---|---|
| `win-gha-core` | Lightweight Windows Server Core runner with Git, PowerShell 7, and .NET 10 SDK |
| `win-gha-buildtools` | Optional heavier Windows runner with Visual Studio Build Tools/MSBuild |
| `ubuntu-gha-core` | Lightweight Linux runner for general CI and .NET builds |
| `nas-beefy` | Optional high-capacity NAS/server runner group for heavy jobs |

## Target fleet

The default design is intentionally simple and non-HA for runners: one lightweight Linux runner and one lightweight Windows runner per Proxmox node.

| Proxmox node | Local orchestrator | Linux runner | Windows runner |
|---|---|---|---|
| `pve01` | `gha-orch01` | `gha-linux01` | `gha-win01` |
| `pve02` | `gha-orch02` | `gha-linux02` | `gha-win02` |
| `pve03` | `gha-orch03` | `gha-linux03` | `gha-win03` |

There is no shared-runner HA layer. If a Proxmox node is down, its local orchestrator and its two runners are offline. The remaining nodes continue serving jobs whose labels match available online runners. See `docs/runner-fleet.md`, `docs/nas-runner-group.md`, and `orchestrator/README.md`.


## Optional NAS / beefy runner group

A NAS or larger server can be added as a separate high-capacity runner group. Keep it opt-in with labels such as `nas`, `beefy`, or `vs-buildtools` so normal jobs continue using the lightweight Proxmox fleet.

Example heavy Linux job:

```yaml
runs-on: [self-hosted, linux, x64, dotnet10, beefy]
```

Example heavy Windows Build Tools job:

```yaml
runs-on: [self-hosted, windows, x64, dotnet10, vs-buildtools]
```

## Two-stage model

### 1. Packer builds golden templates

Packer creates clean VM templates from installation media:

- Windows Server Core templates from ISO + `autounattend.xml`.
- Linux templates from ISO/cloud-init.
- Base OS configuration, WinRM/SSH readiness, guest agent installation, cleanup.

### 2. Ansible configures and registers clones

Ansible installs CI tooling and registers actual cloned VMs as GitHub Actions runners:

- Git
- PowerShell 7
- .NET 10 SDK
- Optional Visual Studio Build Tools/MSBuild
- GitHub Actions runner package
- Runner registration/bootstrap

Runner registration should happen only after cloning/resetting a VM from the clean template or snapshot. GitHub runner registration tokens are short-lived and should never be baked into images.

## Example runner labels

Use explicit self-hosted labels in workflows instead of `windows-latest` or `ubuntu-latest`. The default labels are organization/project neutral so the same runners can be reused by multiple repositories.

Windows runner example:

```yaml
runs-on: [self-hosted, windows, x64, dotnet10]
```

Linux runner example:

```yaml
runs-on: [self-hosted, linux, x64, dotnet10]
```

Optional node-specific routing:

```yaml
runs-on: [self-hosted, linux, x64, dotnet10, pve01]
```

Optional heavier Windows Build Tools runner:

```yaml
runs-on: [self-hosted, windows, x64, dotnet10, vs-buildtools]
```

## Quick start

Install Packer and Ansible on your management machine.

Install Ansible collections:

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

Copy example configuration files and edit locally:

```bash
cp ansible/inventory/hosts.example.ini ansible/inventory/hosts.ini
cp ansible/group_vars/windows.example.yml ansible/group_vars/windows.yml
cp ansible/group_vars/linux.example.yml ansible/group_vars/linux.yml
cp ansible/group_vars/vault.example.yml ansible/group_vars/vault.yml
```

Encrypt real secret values:

```bash
ansible-vault encrypt ansible/group_vars/vault.yml
```

Create a local Packer var file from the example:

```bash
cp packer/windows/vars.example.pkrvars.hcl packer/windows/local.auto.pkrvars.hcl
```

Do not commit the real var file.

## Safety

Never commit:

- GitHub PATs
- GitHub runner registration tokens
- Proxmox API tokens
- Windows administrator passwords
- Ansible vault password files
- Real inventory files with internal hostnames/IPs if you want to keep them private

Use `.example.*` files for committed examples.
