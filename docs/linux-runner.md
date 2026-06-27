# Linux Runner Notes

The Linux runner template is intended for lightweight CI jobs:

- .NET builds and tests
- Scripts
- Packaging
- Static analysis
- Repo maintenance jobs

Linux runners are usually easier and cheaper to maintain than Windows runners, so use them whenever Windows-specific build tooling is not required.

## Example workflow

```yaml
name: linux-build

on:
  push:
  pull_request:

jobs:
  build:
    runs-on: [self-hosted, linux, x64, dotnet10]

    steps:
      - uses: actions/checkout@v4

      - name: Show environment
        run: |
          dotnet --info
          git --version

      - name: Build
        run: dotnet build -c Release
```


## Fleet placement

Linux runners are deployed as `gha-linux01`, `gha-linux02`, and `gha-linux03`, one per Proxmox node. They are the preferred default for lightweight .NET and scripting jobs.

See `runner-fleet.md` for the full non-HA layout and label strategy.
