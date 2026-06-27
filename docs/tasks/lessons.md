# Lessons

Correction patterns and recurring mistakes. Append a dated entry after any user
correction or hard-won lesson. Newest first.

<!-- - YYYY-MM-DD: <what went wrong> -> <the rule to follow next time> -->

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
