# gha-runner-images — current status

_Update only when durable project status changes: major feature completed, known
limitation discovered, milestone changed, or durable architectural direction changed.
Prefer appending dated notes over rewriting._

## Status

**Live: a 3-node self-sustaining JIT ephemeral GitHub Actions runner fleet on
Proxmox + Ceph.** Windows and Linux golden templates build reproducibly with Packer.
Per-node orchestrator LXCs (gha-orch01/02/03) run on systemd timers and cycle a Linux
JIT runner each (gha-linux-eph01/02/03): rollback clean snapshot → generate JIT config →
inject via guest agent → `run.sh --jitconfig` → one job → shutdown → repeat. No laptop in
the runtime path. See ADR-0001 for the target architecture and the dated notes below for
the build-up. The `dotnet_sdk` / `github_runner` roles and the persistent-runner path
(Phase 1) also work.

## Known limitations

- **Windows ephemeral not baked yet** — the Windows template (106) exists but has no JIT
  waiter; only Linux ephemeral runners are live.
- **No HA builder yet** (Phase 4) — templates are still rebuilt from WSL via
  `/template-build`, not by an on-cluster HA builder LXC on a schedule.
- No lint/validate CI on the repo (shellcheck runs locally via a hook).

## Recent notes

<!-- Append dated notes here, newest first: -->
<!-- - YYYY-MM-DD: ... -->
- 2026-07-03: **Windows template rebuilt all-in-one + verified.** New template (106) bakes
  Git + .NET 10 SDK + PowerShell 7 (pwsh) + Visual Studio Build Tools (MSBuildTools +
  ManagedDesktop + VCTools + VC.Tools.x86.x64 + Windows 11 SDK) + runner + boot-waiter
  (clock-fix + LAN trigger). Covers MSBuild, .NET Framework/desktop, native C++, and
  Windows Native AOT (needs the MSVC linker). Re-seeded win slots 321/323 from 106 with
  vmstate clean; runners now advertise vs-buildtools. Verified via a real job: windows
  smoke used `shell: pwsh` and vswhere-found VC.Tools -> success. GOTCHA: vs/18 bootstrapper
  URL was invalid ("file corrupted and unreadable" at Start-Process) -> use vs/17 (VS 2022)
  + size-check the download. buildtools now IN the core Windows image (separate
  windows-gha-buildtools image redundant). Fleet 5/5.
- 2026-07-02: **Verified with a real job — full loop passes.** Dispatched a smoke workflow
  (linux + windows) and both jobs ran on the ephemeral runners and succeeded: job landed
  (gha-linux-eph02 + gha-win-eph01 went busy) -> baked toolchain ran (git 2.43, dotnet,
  cmake, node on linux; dotnet/git on windows via `shell: powershell`) -> JIT auto-removed
  -> VM shut down -> respawned -> 5/5 back online idle. GOTCHA: the fleet repo is PUBLIC and
  the org Default runner group has allows_public_repositories=false (fork-PR safety), so
  public repos can't use the org runners; test from a PRIVATE repo (created
  der-pepe-dev/runner-smoke). Windows has Windows PowerShell 5.1 (works); pwsh 7 is baked in
  the template config but not in the running slots until the Windows rebuild.
- 2026-07-02: **Faster respawn — 15s timer (#1) + LAN self-trigger (#2).** Timer 1min->15s.
  Plus a socket-activated reconcile (gha-orch-trigger.socket on :9099) that a finished
  runner pokes right before shutdown (ORCH_TRIGGER_URL injected into the runner env; both
  bootstraps curl it) — resets the slot immediately instead of waiting for the timer.
  LAN-only, idempotent, no public ingress (the LXCs are NAT'd, so a real GitHub webhook
  would need Cloudflare Tunnel — not worth it here). Proven: manual poke -> reset in ~3s.
  Also baked pwsh into the Windows template (was missing; needs the Windows rebuild).
  Fleet 5/5 online. See lessons.md for the resnap-vs-trigger gotcha that hit slot 311.
- 2026-07-02: **Windows ephemeral on the vmstate fast-path too (~29s).** Converted the
  Windows slots (321 pve1, 323 pve3) to vmstate (RAM) `clean` snapshots and patched their
  baked windows-runner-once.ps1 with the HTTPS-Date clock step (vmstate freezes the Windows
  clock like Linux). gha-win-eph01 online in 29s (was ~50-60s cold). Full fleet now: 3 linux
  (~15s) + 2 windows (~29s), all JIT, all cycling autonomously.
  FOLLOW-UP: both golden templates (108 linux, 107 windows) still carry the pre-clock-fix
  bootstraps — the LIVE slots are patched + committed, but rebuild both templates (repo has
  the fixes) before any re-seed, or a re-seed will regress the clock fix.
- 2026-07-02: **Windows ephemeral runners work.** Rebuilt the Windows template (107)
  baking Git + .NET 10 SDK + the runner package (unregistered) + a SYSTEM at-startup
  Scheduled Task (gha-runner-waiter.ps1) that waits for the orchestrator-injected
  C:\gha-runner\runner.env.ps1 then runs windows-runner-once.ps1 (run.cmd --jitconfig).
  Proven end-to-end on pve1 (gha-win-eph01): stopped -> timer reset -> cold boot ~50s ->
  waiter -> run.cmd --jitconfig -> online + running a job -> cycle. Windows slots on
  pve1 + pve3 only (pve2 too tight on RAM for an 8 GB Windows VM). Off-state snapshot for
  now (~50-60s cold); vmstate + the clock-step fix can speed it later.
- 2026-07-02: **Fast-path recovery via vmstate (RAM) snapshots — ~12-17s.** `clean`
  snapshots now include RAM: rollback restores a live, agent-up, waiter-polling VM in
  seconds, skipping the ~60-90s cold boot. Orchestrator changes: skip start when rollback
  already left the VM running (poll for 'running' to avoid a 409-on-start crash), and
  delete any stale same-name runner before generate-jitconfig (a JIT config that never
  connected lingers offline and 409s). KEY GOTCHA: a vmstate restore freezes the guest
  clock (seen ~1h40m behind) which breaks JIT/token auth — the linux bootstrap now steps
  the clock from an HTTPS Date header before run.sh. Reconcile cron also 1min (was 2). Live
  slots patched + re-vmstate-snapshotted; the Linux TEMPLATE (108) still has the pre-fix
  bootstrap, so rebuild it (repo has the fix) before the next re-seed.
- 2026-07-02: **CI toolchain baked into the Linux runner + fleet re-seeded.** Template 108
  bakes .NET 10 SDK (incl. Native AOT via clang+zlib), cmake, ninja, mingw-w64, binutils,
  sqlite3, ffmpeg, zip, python3, PowerShell 7, and Node.js LTS (extensible via
  runner_apt_packages / dotnet_channel / install_nodejs / dotnet_workloads). Android
  dropped from the core image (too heavy → future beefier image). Re-seeded slots
  311/312/313 from 108; verified on a live slot (dotnet 10.0.109, cmake 3.28.3, node
  v24.18, mingw 13, clang 18.1.3). Runners cycle jobs with the toolchain ready.
- 2026-07-02: **3-node fleet live.** Scaled the JIT orchestrator to all nodes: gha-orch02
  (pve2, LXC 291) + gha-orch03 (pve3, LXC 292), each provisioned via
  install-orchestrator.sh, pointing at its OWN node API (autonomous, no cross-node dep),
  managing a Linux slot cloned from the Ceph template 107 (312 on pve2, 313 on pve3).
  All three per-node runners (gha-linux-eph01/02/03) register via JIT and sit ONLINE idle,
  each cycled by its node's systemd timer. Fully self-sustaining, no laptop. Remaining:
  Windows ephemeral bake, Phase 4 HA builder.
- 2026-07-02: **Refactored to JIT runners.** Orchestrator now calls generate-jitconfig
  (org/repo) and injects RUNNER_JITCONFIG; bootstraps drop config.sh and run
  `run.sh --jitconfig <blob>` (one job → shutdown). No registration token or
  .runner/.credentials on disk (env file deleted after read), inherently single-use,
  and it sidesteps the config.sh update/deprecation dance. Rebuilt the Linux template
  with the JIT bootstrap, redeployed the script to gha-orch01, verified end-to-end via
  the LXC timer: reconcile → JIT injected → runner ONLINE idle (waiting for jobs). PAT
  still stays on the orchestrator; the runner only sees the one-shot encoded config.
- 2026-07-01: **Phase 3 proven — autonomous orchestrator LXC.** Deployed gha-orch01
  (unprivileged Ubuntu 24.04 LXC on pve1, vmid 290) via orchestrator/install-orchestrator.sh:
  installs curl+jq, the orchestrator + eval-age scripts, config
  (/etc/gha-local-orchestrator/node.local.env), a 0600 secrets EnvironmentFile, and the
  systemd service+timer. On its ~2-min timer it reconciled slot 311 with NO laptop:
  rollback clean → inject token → waiter registered gha-linux-eph01 --ephemeral → online +
  running a job. Also baked runner 2.335.1 (2.329.0 was deprecated) + --disableupdate.
  The self-sustaining ephemeral fleet is live. Remaining: replicate to pve2/3, Windows
  ephemeral bake, Phase 4 HA builder.
- 2026-07-01: **Phase 2 ephemeral loop proven end-to-end.** orchestrate-once against a
  1-slot node.local.env cycled gha-linux-eph01 (vmid 311, cloned from baked template 108):
  rollback to `clean` snapshot → start → guest agent → mint org token → inject
  /etc/gha-runner/env via agent file-write → baked gha-runner-waiter.service ran
  linux-runner-once.sh → runner registered `--ephemeral` and came ONLINE + picked up a
  job. Key fix found: baked runner auto-update deletes the one-shot ephemeral registration
  mid-update → added `--disableupdate` to both bootstrap scripts. Also: agent
  network-get-interfaces is a GET not POST (pve-status agent() to fix). Control-plane
  skills (runner-slot/teardown/template-build/orchestrate-once) + shellcheck hook added.
- 2026-06-27: **First runner registered (Phase 1 done).** Full pipeline proven:
  Linux template (107) → full clone → Ansible `linux-register-runner.yml` (github_runner
  role, org scope) → gha-linux01 registered to der-pepe-dev as a systemd service runner.
  Fixes that got it working: group_vars moved to inventory/group_vars (so playbooks load
  it), ansible.cfg yaml callback → default+result_format, force ANSIBLE_CONFIG on WSL
  /mnt (world-writable cfg ignored), Linux template self-regenerates SSH host keys on
  clone, register playbooks no longer override github_owner, accept 201 from
  registration-token. Next: Phase 2 — orchestrator snapshot-rollback loop.
- 2026-06-27: **Windows golden template built + hardened** (`tmpl-win-gha-core`, VMID 106)
  on the Ceph-backed pve1/2/3 cluster. Now full **virtio** (virtio-scsi disk via vioscsi
  WinPE injection + virtio NIC), **Windows Update** baked in (toggleable `install_updates`,
  Defender defs excluded), and `cpu_type = host`. Full working recipe captured in
  lessons.md; build reproducible (~32 min with updates). Note: template 106 was built
  before the cpu_type change loaded — flip with `qm set 106 --cpu host`. Next: re-run
  discovery for fleet.local.yml, then clone + register a runner.
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
