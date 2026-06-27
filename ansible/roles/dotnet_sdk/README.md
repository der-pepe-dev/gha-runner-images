# dotnet_sdk role

Installs the .NET SDK on a runner, on either Linux (ssh) or Windows (winrm), using the
official `dotnet-install` script.

- Linux: installs to `{{ dotnet_install_dir_linux }}` (default `/opt/dotnet`) and symlinks
  `dotnet` into `/usr/local/bin`.
- Windows: installs to `{{ dotnet_install_dir_windows }}` (default
  `C:\Program Files\dotnet`) and adds it to the machine PATH.

Platform is selected from `ansible_connection` (`winrm` → Windows), so it works in plays
that run with `gather_facts: false`.

## Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `dotnet_channel` | `"10.0"` | SDK channel (`10.0`, `8.0`, `LTS`, …) |
| `dotnet_install_dir_linux` | `/opt/dotnet` | Linux install dir |
| `dotnet_install_dir_windows` | `C:\Program Files\dotnet` | Windows install dir |

## Usage

```yaml
- hosts: linux
  become: true
  roles:
    - dotnet_sdk
```
