# Local Runner Orchestrator

The recommended fleet model is one tiny local orchestrator per Proxmox node.

```text
pve01: gha-orch01 manages gha-linux01 and gha-win01
pve02: gha-orch02 manages gha-linux02 and gha-win02
pve03: gha-orch03 manages gha-linux03 and gha-win03
```

This keeps failure domains simple. If a node is offline, its local orchestrator is offline too, and that is fine because its local runners are also offline.

## Responsibilities

A local orchestrator should:

- Check only the runner VMs assigned to its node.
- Detect stopped/missing disposable runner VMs.
- Roll back a clean snapshot or recreate from a local template.
- Request a fresh GitHub runner registration token.
- Inject bootstrap settings such as runner name, URL, token, labels, and ephemeral mode.
- Start the runner VM.

## What it should not do

- It should not manage runner slots on other Proxmox nodes.
- It should not need Proxmox HA.
- It should not store long-lived runner registration tokens.
- It should not include project-specific labels by default.


## Runner bootstrap scripts

The `bootstrap/` directory contains one-shot runner bootstrap examples:

- `linux-runner-once.sh` registers with `--ephemeral`, runs one job, then shuts down.
- `windows-runner-once.ps1` registers with `--ephemeral`, runs one job, then shuts down.

Bake these scripts into the runner templates or inject them during provisioning. The local orchestrator should inject fresh values for `RUNNER_URL`, `RUNNER_TOKEN`, `RUNNER_NAME`, and `RUNNER_LABELS` before each boot/reset.

## Orchestrator container

```text
1 vCPU
512 MB-1 GB RAM
4-8 GB disk
Debian/Ubuntu minimal LXC (unprivileged)
systemd timer every 1-5 minutes
```

**Distro:** a minimal Debian/Ubuntu LXC is the recommended base. It keeps the systemd
service + timer in this directory working with no rework, and `bash`/`curl` are already
present — only `jq` needs installing:

```sh
apt-get update && apt-get install -y jq
```

A tinier base (e.g. Alpine) would shave ~100 MB but is not worth it here: that saving is
rounding error against the runner VMs (4-80 GB), and Alpine would mean no systemd (cron
or OpenRC instead) plus `apk add bash` since the scripts need real bash, not ash. Keep
it boring and consistent.

**Run it unprivileged.** This container holds Proxmox and GitHub tokens (via the systemd
`EnvironmentFile`), so it should be an **unprivileged** LXC. It needs only outbound
network to the Proxmox API and GitHub — no host device passthrough, no privileged
mounts. Unprivileged is the recommended default precisely because of the credentials it
carries.

The scripts in this directory are scaffolds. Replace placeholder API calls and injection logic with your preferred Proxmox/cloud-init/guest-agent workflow.

## Implementation notes

- The orchestrator is **bash** (`gha-local-orchestrator.sh`) to keep the LXC lean —
  its only dependencies are `bash`, `curl`, and `jq` (no PowerShell/.NET runtime).
- Per-node config is a flat, shell-sourceable `.env` file
  (`node01.example.env` / `nas01.example.env` → copy to `node.local.env`). Slots are
  expressed as `SLOT_COUNT` plus indexed `SLOT_<n>_*` variables — no YAML parser needed.
- Secrets (`PROXMOX_TOKEN_ID`, `PROXMOX_TOKEN`, `GITHUB_TOKEN`) come from the systemd
  `EnvironmentFile`, never the config file.
- The Linux runner bootstrap is bash; the **Windows** runner bootstrap stays PowerShell
  (`bootstrap/windows-runner-once.ps1`) since it runs on Windows.

## Windows template eval-age check

Windows runner templates are built from an **evaluation** ISO, so the activation
clock (180 days for Server 2022) starts when the `win-gha-core` template is built.
`check-windows-template-age.sh` runs on the orchestrator and warns before that
clock runs out, so the template is regenerated (or rearmed) in time.

- **Alert only** — it never rebuilds. It reads each Windows template's creation
  time from Proxmox (`/qemu/<vmid>/config` → `meta` → `ctime`), computes age, and
  warns at/over `WIN_TEMPLATE_EVAL_MAX_DAYS` (default 100). No state file.
- It checks the `SLOT_<n>_TEMPLATE_VMID` of every slot with `SLOT_<n>_OS=windows`.
- Exit non-zero = at least one template overdue (or its `ctime` is unreadable).

Install alongside the orchestrator and enable the daily timer:

```sh
install -m 0755 check-windows-template-age.sh /opt/gha-local-orchestrator/
install -m 0644 gha-template-age-check.service gha-template-age-check.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now gha-template-age-check.timer
```

When it warns, regenerate the template (`packer build .../windows-gha-core.pkr.hcl`)
or rearm the running template (`slmgr /rearm`, then reboot) to reset the eval clock.
See `../docs/windows-runner.md` for the rearm-vs-rebuild tradeoff.

## Optional NAS orchestrator

If a NAS or larger server hosts an additional high-capacity runner group, prefer a local orchestrator there too:

```text
nas01: gha-nas-orch01 manages gha-nas-linux01 and optional gha-nas-win01
```

Keep this separate from the lightweight Proxmox-node orchestrators. Use opt-in labels such as `nas`, `beefy`, or `vs-buildtools` so only heavy workflows target it.
