# Windows Runner Notes

Windows Server Core is preferred for CI runners because it is lighter than Desktop Experience while still supporting .NET SDK builds and command-line build tooling.

## Image types

### `win-gha-core`

Minimal Windows runner:

- Windows Server Core 2022/2025
- Git for Windows
- PowerShell 7
- .NET 10 SDK
- GitHub Actions runner package/registration support

Use this first for SDK-style .NET builds.

### `win-gha-buildtools`

Heavier Windows runner:

- Everything in `win-gha-core`
- Visual Studio Build Tools
- MSBuild workload
- Managed Desktop Build Tools workload

Use this only when projects require Visual Studio/MSBuild desktop build components.

## Evaluation licensing & template regeneration

The Windows templates are built from a **Windows Server evaluation** ISO. The eval
activation clock (180 days for Server 2022) starts when the template VM is built,
**not** when a runner is cloned. If the template ages out, every clone inherits an
expired/expiring eval.

To stay ahead of it:

- The orchestrator runs `check-windows-template-age.sh` daily and **alerts** when a
  Windows template reaches `WIN_TEMPLATE_EVAL_MAX_DAYS` (default 100 days — an 80-day
  buffer before the 180-day limit). It derives age from the template VM's Proxmox
  `ctime`, so there is no separate state file to keep in sync. See
  `../orchestrator/README.md`.
- On alert, pick one:
  - **Regenerate (preferred, ~100-day cadence):** rerun
    `packer build packer/windows/windows-gha-core.pkr.hcl`. Clean OS install, fresh
    eval clock, latest patches/tooling baked in. Then re-take the `clean` snapshot
    the orchestrator clones from.
  - **Rearm (stopgap):** `slmgr /rearm` on the template, then reboot, resets the
    180-day clock without a rebuild. Server 2022 allows up to ~5 rearms. Cheaper but
    drifts further from current patches — use only to buy time, not as the plan.

Regeneration is the durable answer; rearm is the escape hatch.

## Runner registration

Do not bake runner registration into templates. Register only cloned VMs, because runner names should be unique and GitHub registration tokens are short-lived.

## Example workflow

```yaml
name: build

on:
  push:
  pull_request:

jobs:
  build:
    runs-on: [self-hosted, windows, x64, dotnet10]

    steps:
      - uses: actions/checkout@v4

      - name: Show environment
        shell: pwsh
        run: |
          dotnet --info
          git --version

      - name: Restore
        shell: pwsh
        run: dotnet restore

      - name: Build
        shell: pwsh
        run: dotnet build -c Release --no-restore

      - name: Test
        shell: pwsh
        run: dotnet test -c Release --no-build --verbosity normal
```


## Fleet placement

Windows runners are deployed as `gha-win01`, `gha-win02`, and `gha-win03`, one per Proxmox node. Use the optional `win-gha-buildtools` image only for jobs that really need Visual Studio Build Tools.

See `runner-fleet.md` for the full non-HA layout and label strategy.
