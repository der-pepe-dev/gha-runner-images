# Runner consumers

The projects whose CI runs on the self-hosted runners built by this repo, and what
each needs installed. This is the **hub** for fleet CI requirements: when a project
needs a tool on a runner, it records that need in its own `docs/ci-requirements.md`
and the corresponding row here is added/updated in the same change.

Keep this informational. Agents working in a consumer project do not edit other
projects; they record their own need locally and a maintainer reflects it here.

## How a project requests a runner change

1. The project records the dependency in its own `docs/ci-requirements.md`.
2. A change to this repo adds/updates the project's row below and installs the tool
   in the relevant Ansible role/playbook (Linux and/or Windows).
3. Re-provision the affected runners (registration playbooks run on clones only).

## Consumers

> **Label model:** runners use generic labels (`[self-hosted, linux, x64, dotnet10]`)
> plus a node label, and are **ephemeral** (one job per boot). Project-specific labels
> are not baked into runners by default — projects select runners by capability
> (os/arch/dotnet/`vs-buildtools`/`nas`), not by project name. The "Runner labels"
> column below is what each project's jobs target, not a dedicated runner.


| Project | Runner labels | Tools needed beyond base image |
|---|---|---|
| DePam | `[self-hosted, linux, x64, dotnet10]`, `[self-hosted, windows, x64, dotnet10, vs-buildtools]` | mingw-w64 cross-compile toolchain, CMake, Ninja (native cores); binutils for binary inspection |
| ArtifactView | `[self-hosted, windows, x64, dotnet10]` | net10.0-windows build; GDI+ / Windows desktop libs |
| DedupSharp | `[self-hosted, linux, x64, dotnet10]` | base .NET only |
| ReMedia | `[self-hosted, windows, x64, dotnet10]` | ffmpeg, ffprobe (WPF desktop build) |
| FileAudit | `[self-hosted, linux, x64, dotnet10]` | ffmpeg/ffprobe (optional), sqlite3, zip tools |

## Base image contents (for reference)

Defined by the Packer + Ansible automation in this repo:
- Git, PowerShell 7, .NET 10 SDK (all runners)
- **Linux runner** also bakes (packer/linux, `runner_apt_packages` + vars): build-essential,
  clang + zlib1g-dev (Native AOT), cmake, ninja, mingw-w64, binutils, gdb, sqlite3, ffmpeg,
  zip/unzip, python3, Node.js LTS, and the `android` .NET workload. Android SDK/JDK are NOT
  baked — Android jobs provide those (setup-java / android-actions).
- Visual Studio Build Tools / MSBuild (the `vs-buildtools` Windows runner only)

Anything a project lists above that is **not** in the base image needs a role/playbook
change here.

## Notes

- Tool lists reflect what each project's docs declare; verify against the project's
  `docs/ci-requirements.md` before changing a role.
- Runner labels are the contract — changing them affects the consuming projects'
  `runs-on:` lines.
