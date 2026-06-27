# gha-runner-images — current status

_Update only when durable project status changes: major feature completed, known
limitation discovered, milestone changed, or durable architectural direction changed.
Prefer appending dated notes over rewriting._

## Status

Scaffold in active development. The two-stage Packer→Ansible structure, secret
hygiene, register-runner playbooks, and a new **local-orchestrator fleet model**
(per-node orchestrator managing ephemeral runners; optional NAS capacity pool) are in
place. Fleet cloning (`scripts/clone-runner-fleet.ps1` + `fleet.example.yml`) and
orchestrator scaffolds (`orchestrator/`) are present. Intentionally incomplete:
Ansible roles are placeholder stubs, the Linux Packer build is a skeleton, and the
orchestrator scripts are scaffolds with placeholder Proxmox/injection logic.

## Known limitations

- Ansible roles (`dotnet_sdk`, `github_runner`, `windows_buildtools`) are README stubs.
- Linux Packer build needs autoinstall boot command + cloud-init media to be automated.
- No lint/validate CI on this repo yet.

## Recent notes

<!-- Append dated notes here, newest first: -->
<!-- - YYYY-MM-DD: ... -->
