# Lessons

Correction patterns and recurring mistakes. Append a dated entry after any user
correction or hard-won lesson. Newest first.

<!-- - YYYY-MM-DD: <what went wrong> -> <the rule to follow next time> -->

### 2026-06-27: Windows Packer build on Proxmox — full working recipe

First successful Windows template (`tmpl-win-gha-core`, VMID 106) took a long chain of
fixes. The complete set of requirements, so the next build (buildtools, rebuilds) just
works:

**Build host (WSL2):** install `xorriso` — Packer builds the `cd_files` CD locally before
upload; without it: "could not find a supported CD ISO creation command".

**Proxmox token privileges** (`packer@pve`, token `--privsep 0`):
`PVEVMAdmin` on `/`, `PVEDatastoreAdmin` on `/storage` (AllocateTemplate, to upload the
build CD), `PVESDNUser` on `/sdn` (SDN-managed bridges). Pass the secret with
`-var "proxmox_token=$PROXMOX_TOKEN"` — a var-file value overrides `PKR_VAR_*`.

**VM hardware (in the .pkr.hcl):**
- `bios = "ovmf"` + `efi_config` — autounattend uses a GPT layout; legacy SeaBIOS fails
  `<DiskConfiguration>`.
- `boot_command` spamming `<enter>` — get past the UEFI "Press any key to boot from CD".
- Disk `type = "sata"` and NIC `model = "e1000"` — WinPE/clean Windows has no virtio
  driver, so a virtio-scsi disk is invisible at install and a virtio NIC has no network.
- Mount the **virtio-win ISO** (`virtio_iso`) — needed for the guest agent.

**autounattend (gitignored; commit only `.example`):**
- Admin password must equal `winrm_password` (it becomes the template's Administrator
  password); mismatch → infinite "Waiting for WinRM".
- FirstLogon must **search drives** for the scripts (PowerShell `Get-PSDrive`), not
  hardcode `D:` — multiple mounted ISOs shift the build CD's letter.
- FirstLogon installs the QEMU guest agent (Proxmox builder discovers the VM IP via the
  agent; it must be up *before* WinRM), then enables WinRM.

**Guest agent install (`install-qemu-guest-agent.ps1`):**
- Install virtio drivers via `pnputil /add-driver ... /subdirs /install` first — the agent
  reaches the host over virtio-serial (vioser); MSI alone → "agent not running".
- Pre-trust the Red Hat publisher cert from the **`.cat`** files (virtio is catalog-signed;
  `.sys` have no embedded signature) into machine TrustedPublisher+Root, or the
  "install this device software?" dialog hangs the unattended build.
- End best-effort scripts with `exit 0` — `pnputil` returns non-zero when bundled drivers
  match no device, which would otherwise fail the provisioner.

**Rule:** the guest agent + virtio drivers run at FirstLogon (needed for IP discovery), so
do NOT also list `install-qemu-guest-agent.ps1` as a provisioner. `cleanup.ps1` clears
`C:\Windows\Temp`, which deletes Packer's env-vars helper — keep it the LAST provisioner
(cosmetic error only).

### 2026-06-27: SDN-managed bridges — hidden from /network, need SDN.Use

**What went wrong:** `vmbr0` never appeared in `/nodes/<node>/network` (only physical
NICs did), and `packer build` failed with `403 ... (/sdn/zones/localnetwork/vmbr0,
SDN.Use)`. The bridge is **SDN-managed** (zone `localnetwork`), so it lives under
`/sdn`, not the node network list.

**Rule:** Detect the bridge from an existing VM's `net0` (discover-proxmox.sh does this),
not just `/nodes/<node>/network`. For the Packer token on an SDN cluster, grant
`PVESDNUser` on `/sdn` (`SDN.Use`) in addition to `PVEVMAdmin` + `PVEDatastoreAdmin`.

### 2026-06-27: Packer build token privileges (Proxmox)

**What went wrong:** Hit a sequence of build failures — `401` (token secret shadowed by a
var-file `proxmox_token = "CHANGE_ME"`), `403 Datastore.AllocateTemplate` (PVEDatastoreUser
too weak to upload the build CD ISO), `403 SDN.Use`.

**Rule:** Full Packer build grant = `PVEVMAdmin` on `/`, **`PVEDatastoreAdmin`** on
`/storage` (AllocateTemplate, not just …User/AllocateSpace), and `PVESDNUser` on `/sdn`
if networking is SDN. Pass the token secret with `-var "proxmox_token=$PROXMOX_TOKEN"`
(a `-var-file` value overrides `PKR_VAR_*`), never as a CHANGE_ME line in the var-file.

### 2026-06-27: `proxmox-iso` has no `shutdown_command`; validate Packer from its dir

**What went wrong:** The Windows templates carried `shutdown_command = "...cleanup.ps1"`,
which the `proxmox-iso` builder rejects (`argument ... not expected`) — so they never
validated. The builder stops the VM itself after provisioning. Also `cd_files` paths are
resolved relative to the **current working directory**, not the template file, so
`packer validate` must run from `packer/windows/`.

**Rule:** For `proxmox-iso`, do cleanup as the last provisioner (no `Stop-Computer`/
shutdown in it) and let the builder stop the VM — don't add `shutdown_command`. Run
`packer validate -var-file=vars.example.pkrvars.hcl <tmpl>` from the template's directory.

### 2026-06-27: Windows paths in YAML need single quotes

**What went wrong:** `runner_zip: "C:\tools\actions-runner...zip"` — double-quoted YAML
parsed `\t`→TAB and `\a`→BEL, corrupting the path to `C:<TAB>ools\x07ctions...`.

**Rule:** Always single-quote Windows paths (`'C:\tools\...'`) or use forward slashes in
YAML. Bare scalars are also safe; double quotes are the trap.

### Orchestrator is bash, not PowerShell (lean LXC)

**Decision:** The local orchestrator runs on a tiny Debian/Ubuntu LXC (512MB-1GB). It
is written in **bash** (`curl` + `jq`), not PowerShell, to avoid the ~150MB+ .NET
runtime on a container whose only job is a reconcile timer. Per-node config is a flat
shell-sourceable `.env` (indexed `SLOT_<n>_*` vars), avoiding a YAML parser dependency.

**Rule:** Keep the Linux orchestrator dependency set to bash/curl/jq. The Windows
*runner bootstrap* stays PowerShell because it executes on Windows — that split is
intentional (native tool for where it runs), not an inconsistency to "fix."

### Orchestrator LXC: minimal Debian/Ubuntu, unprivileged (not Alpine)

**Decision:** Run the orchestrator on a minimal Debian/Ubuntu LXC, unprivileged.
Considered Alpine for size but rejected it: the ~100MB saving is rounding error vs the
runner VMs (4-80GB), and Alpine would drop systemd (cron/OpenRC instead) and need
`apk add bash` (scripts need real bash, not ash). Minimal Debian/Ubuntu keeps the
systemd unit/timer working with no rework; only `jq` needs installing.

**Rule:** Keep the orchestrator on minimal Debian/Ubuntu + systemd. Run it
**unprivileged** — it holds Proxmox and GitHub tokens and needs only outbound network.
Don't "optimize" it onto Alpine; the consistency is worth more than the megabytes.

### 2026-06-27: Generalized Linux template must self-regenerate SSH host keys

**What went wrong:** The generalize step removed /etc/ssh/ssh_host_* but clones did not
regenerate them (cloud-init has no datasource on a plain clone), so sshd reset every
connection (`kex_exchange_identification: Connection reset by peer`).

**Rule:** Don't rely on cloud-init for host-key regen on clones. Install a first-boot
systemd oneshot (`Before=ssh.service`, `ConditionPathExistsGlob=!/etc/ssh/ssh_host_*_key`,
`ExecStart=/usr/bin/ssh-keygen -A`) before removing the keys. Same idea applies to any
"remove identity then regenerate on boot" generalize step.
