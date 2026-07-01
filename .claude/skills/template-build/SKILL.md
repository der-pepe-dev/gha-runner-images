---
name: template-build
description: Build a golden Proxmox template with Packer (linux / windows / buildtools) from the right directory with the build token wired in. Use when the user wants to (re)build a runner image. Long-running — run it in the background.
---

# template-build

Wraps `packer build` for the three images, pulling `PROXMOX_TOKEN` from the shared
gitignored `.claude/skills/pve-status/pve.local.env` (must be build-privileged:
PVEVMAdmin + PVEDatastoreAdmin + PVESDNUser) and the per-OS `local.pkrvars.hcl`
(from discover-proxmox.sh).

```bash
S=.claude/skills/template-build/template-build.sh
bash "$S" linux                          # rebuild the Ubuntu template
bash "$S" linux -var install_updates=false   # fast test build (skip updates)
bash "$S" windows
bash "$S" buildtools
```

**Always run this in the background** (it's 8-40 min) and report the new template VMID
from the tail (`A template was created: <vmid>`).

Handover (per ADR-0001): Packer creates a NEW VMID with the same name. After a good
build, destroy the old same-named template (`/pve-status templates` to find it, then
`qm destroy <old>` or the runner-teardown-style API delete). For Windows, set the build
password to match `autounattend.xml`.
