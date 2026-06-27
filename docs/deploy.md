# Deploying images to Proxmox (shared Ceph storage)

How to build the golden templates from this management host (WSL2) onto a Proxmox VE
cluster backed by **shared Ceph storage**. For the two-stage model (Packer template →
Ansible-provisioned clones) see [[runner-architecture]]; for fleet layout see
[[runner-fleet]].

## Mental model: nothing is "copied"

Packer's `proxmox-iso` builder is **remote**. This host never holds an image file. Packer
talks to the Proxmox API (HTTPS, port 8006), creates a VM **on the node** from an ISO
already in Proxmox storage, provisions it over WinRM/SSH, then converts it to a template.

```text
WSL2 (packer) ──HTTPS 8006──> Proxmox API
                                ├─ create VM from ISO (must already be in PVE storage)
                                ├─ provision (WinRM / SSH)
                                └─ convert to template  ← stored on Ceph (cluster-wide)
```

## Why Ceph makes this easy (and the one catch)

Ceph **RBD** is shared block storage. A template whose disk lives on RBD is visible to
**every** node in the cluster, so you **build once and clone anywhere** — no per-node
rebuild, no migration. This is the main win over per-node `local-lvm`.

**The catch:** RBD only holds VM disks (content type `images`/`rootdir`). It **cannot**
store **ISOs** (content type `iso`). Both ISO inputs therefore need a storage that allows
`iso`/`snippets` content:

- The **install ISO** (`iso_file`) — Windows Server / Ubuntu.
- The **build-time CD** Packer generates from `cd_files` (`additional_iso_files` →
  `iso_storage_pool`) — autounattend.xml + the WinRM/cleanup scripts.

Use one of:

- **CephFS** (recommended) — a shared filesystem on the same Ceph cluster, enabled with
  content types `iso` + `snippets`. Upload the install ISO once; all nodes see it.
- A node-local directory (e.g. `local`) — simplest, but the ISO must exist on **each**
  node you build on.

## One-time cluster setup

1. **Enable CephFS for ISOs/snippets** (Datacenter → Storage, or `pvesm`). Give it
   content types `iso,snippets`. Call it e.g. `cephfs`.
2. **Confirm the RBD pool name** for VM disks (e.g. `ceph-vm` or `rbd`). This is your
   Packer `storage_pool`.
3. **Upload install ISOs once** to CephFS:
   ```bash
   # via Proxmox UI (Storage → cephfs → ISO Images → Upload), or scp to a node:
   scp windows-server-2022.iso root@pve01:/mnt/pve/cephfs/template/iso/
   scp ubuntu-24.04-live-server-amd64.iso root@pve01:/mnt/pve/cephfs/template/iso/
   ```
4. **Create a Packer API token** with rights to create/clone/configure VMs and read
   storage (`packer@pve!packer`). Keep the secret out of git.

## Network reachability

This host must reach the API of the node you build on:

```bash
curl -k https://pve01:8006/api2/json/version    # expect a JSON version blob
```

WSL2's NAT normally reaches the LAN. If not, use the node IP and ensure WSL can route to
the Proxmox management network.

## Configure the build for Ceph

**Fast path — auto-detect.** `scripts/discover-proxmox.sh` queries the cluster and writes
`packer/{windows,linux}/local.pkrvars.hcl` with the right storage_pool (prefers Ceph rbd),
iso_storage_pool (prefers cephfs), iso_file, bridge, and node already filled:

```bash
PROXMOX_URL=https://pve01:8006/api2/json \
PROXMOX_TOKEN_ID='packer@pve!packer' PROXMOX_TOKEN='...' \
  scripts/discover-proxmox.sh            # add --include-token to bake the token in
```

It leaves the API token and `winrm_password` as `CHANGE_ME` placeholders. Review the
files, then build. Or do it by hand — the committed examples use per-node `local-lvm` +
`local:iso`; override for Ceph in a **gitignored** local var file
(`*.pkrvars.hcl` / `*.auto.pkrvars.hcl` are gitignored):

```hcl
# packer/windows/local.pkrvars.hcl   (gitignored; do not commit)
proxmox_url      = "https://pve01:8006/api2/json"
proxmox_username = "packer@pve!packer"
proxmox_token    = "REPLACE_ME"          # real secret, never committed
proxmox_node     = "pve01"               # any node; template lands cluster-wide via Ceph

iso_file         = "cephfs:iso/windows-server-2022.iso"   # CephFS, not local:
storage_pool     = "ceph-vm"              # RBD pool for the template disk
iso_storage_pool = "cephfs"               # build-time CD (autounattend); needs iso content

vm_name        = "tmpl-win-gha-core"
winrm_username = "Administrator"
winrm_password = "REPLACE_ME"            # MUST match autounattend.xml (see windows-runner)
```

Also set the **build-CD** storage to an `iso`-capable pool via the `iso_storage_pool`
variable (default `local`). For a Ceph-only cluster set `iso_storage_pool = "cephfs"`, or
keep a small node-local `local` dir for it. The Linux build mounts cloud-init the same way
once that skeleton is completed.

## Build

```bash
cd packer/windows
packer init windows-gha-core.pkr.hcl
packer validate -var-file=local.pkrvars.hcl windows-gha-core.pkr.hcl
packer build    -var-file=local.pkrvars.hcl windows-gha-core.pkr.hcl
```

Repeat with `windows-gha-buildtools.pkr.hcl` and (once finished) the Linux build under
`packer/linux/`. Each produces one template; on Ceph that template is immediately
cluster-wide.

> Build from the template's own directory — `cd_files` paths (`autounattend.xml`, the
> scripts) resolve relative to the current working directory, not the `.pkr.hcl` file.

## After the build: clone the fleet

With templates on Ceph, every node can clone them. Re-run `discover-proxmox.sh` now that
the templates exist — it detects their VMIDs and writes `scripts/fleet.local.yml` (one
Linux/Windows/orchestrator set per node, storage pointed at the RBD pool):

```bash
PROXMOX_URL=https://pve01:8006/api2/json \
PROXMOX_TOKEN_ID='packer@pve!packer' PROXMOX_TOKEN='...' \
  scripts/discover-proxmox.sh --force      # --force to refresh existing files

# Review scripts/fleet.local.yml, then clone:
PROXMOX_TOKEN_ID='packer@pve!packer' PROXMOX_TOKEN='...' \
  pwsh scripts/clone-runner-fleet.ps1 -FleetFile scripts/fleet.local.yml
```

(Or copy `fleet.example.yml` → `fleet.local.yml` and fill it by hand. `full_clone: true`
gives independent disks; `storage` is the RBD pool.)

Then register runners on the **clones only** (never the template) with
`ansible/playbooks/{linux,windows}-register-runner.yml`. See [[runner-architecture]] and
[[windows-runner]] / [[linux-runner]].

## Per-node vs cluster-wide — when you'd still build more than once

- **Same template on Ceph:** build once. Clones can target any node (`target` in the clone
  body), placement is independent of where you built.
- **You only need to rebuild** to refresh the OS/patches or reset the Windows eval clock
  (see [[windows-runner]]) — not to reach another node.

## Checklist

- [ ] CephFS storage with `iso,snippets` content enabled
- [ ] Install ISOs uploaded to CephFS
- [ ] RBD pool name known → `storage_pool`
- [ ] `packer@pve!packer` token created (secret kept out of git)
- [ ] `curl -k https://<node>:8006/api2/json/version` reachable from WSL2
- [ ] Local `*.pkrvars.hcl` overrides `iso_file`/`storage_pool`/`iso_storage_pool` for Ceph
- [ ] `winrm_password` matches `autounattend.xml`
- [ ] `packer build` → template on Ceph → clone fleet → register clones
