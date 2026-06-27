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
- 2026-06-27: **First Windows golden template built** (`tmpl-win-gha-core`, VMID 106)
  via `packer build` onto the Ceph-backed pve1/2/3 cluster. Full working recipe (OVMF,
  SATA/e1000, virtio-win ISO, FirstLogon guest-agent + drive-search, cert pre-trust,
  exit-0 hygiene, build-token privileges incl. SDN.Use) captured in lessons.md. Build is
  now reproducible. Next: re-run discovery to generate fleet.local.yml, then clone +
  register a runner.
- 2026-06-27: Filled `dotnet_sdk` and `github_runner` roles (previously README stubs).
  Both branch Linux/Windows via `ansible_connection` (works with gather_facts:false).
  github_runner keeps the persistent-service behavior with an optional
  `runner_ephemeral` flag. Rewired linux/windows-base (dotnet via role in pre_tasks/
  role/post_tasks order) and the register playbooks (thin role callers). Added
  `roles_path = roles` to ansible.cfg so roles resolve from `ansible/roles`. All four
  playbooks pass `ansible-playbook --syntax-check`. (`windows_buildtools` role still a
  stub; its logic remains in windows-buildtools.yml.)
- 2026-06-27: Repo audit fixes. Windows Packer templates now `packer validate` clean —
  removed invalid `shutdown_command` (proxmox-iso has no such field; it never validated
  before) and stripped `Stop-Computer` from cleanup.ps1 (it runs as a provisioner).
  Fixed corrupted `runner_zip` path in windows-register-runner.yml (YAML double-quote
  `\t`/`\a` escape). Added `-SkipCertificateCheck` to the PS clone scripts (self-signed
  PVE). Doc/polish: README password-match note, trimmed unused `nas_runner_group` from
  fleet.example.yml, annotated gitignored `environment.md` in index, PS verb rename.
- 2026-06-27: Added Windows template eval-age tracking. Templates build from a
  Windows Server eval ISO (180-day clock from build). `orchestrator/check-windows-template-age.sh`
  + daily systemd timer (`gha-template-age-check.{service,timer}`) alert (no auto-rebuild)
  when a Windows template hits `WIN_TEMPLATE_EVAL_MAX_DAYS` (default 100); age derived from
  Proxmox VM `ctime`, no state file. Regenerate via packer or `slmgr /rearm` to reset.
  See windows-runner.md + orchestrator/README.md.
