# Task: complete the Ubuntu Linux Packer build (autoinstall)

Turn `packer/linux/ubuntu-gha-core.pkr.hcl` from a skeleton into a working autoinstalled
Ubuntu 24.04 golden template, mirroring the proven Windows flow but simpler (Ubuntu has
inbox virtio drivers — no injection needed).

## Plan

- **cidata CD**: mount `cloud-init/user-data` + `meta-data` as an `additional_iso_files`
  with `cd_label = "cidata"` (NoCloud datasource).
- **boot_command**: at GRUB, drop to the command line and boot the casper kernel with
  `autoinstall ds=nocloud` so Subiquity runs unattended.
- **user-data**: real Ubuntu autoinstall (identity = `ansible` user + hashed password,
  ssh server, `qemu-guest-agent` + `openssh-server` packages, passwordless sudo). The
  agent is needed so the proxmox-iso builder can discover the VM IP for SSH.
- **source**: virtio-scsi disk + virtio NIC, `cpu_type` (already a var), `bios` default
  (Ubuntu boots fine on SeaBIOS; keep simple), SSH communicator.
- **build block**: minimal cleanup provisioner (cloud-init clean, machine-id reset, ssh
  host keys removed) so clones get unique identity.
- Split secret: like autounattend, the password hash → keep `user-data` example committed,
  real one gitignored if it carries a non-placeholder hash. (Placeholder hash is not a
  secret, so committing user-data with a documented placeholder is fine.)

## Checklist

- [ ] Generate SHA-512 hash for the build password (placeholder, documented)
- [ ] Rewrite cloud-init/user-data as autoinstall; update meta-data
- [ ] Rewrite ubuntu-gha-core.pkr.hcl (cidata CD, ssh, boot_command, virtio, build block)
- [ ] Update packer/linux/vars.example
- [ ] `packer validate`
- [ ] Document in linux-runner.md + deploy.md (Linux build steps)
- [ ] User test on cluster; iterate boot_command/paths as needed

## Notes / expected iteration

- boot_command GRUB paths (`/casper/vmlinuz`, `/casper/initrd`) and timing may need
  tuning against the real 24.04.4 ISO — like the Windows build, expect a couple cycles.
- ssh_password (var) MUST match the hash in user-data (same trap as winrm_password vs
  autounattend).
