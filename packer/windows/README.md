# Windows Packer Templates

This directory contains Packer skeletons for building Proxmox-hosted Windows Server Core GitHub Actions runner templates.

## Templates

- `windows-gha-core.pkr.hcl`: minimal Windows runner template.
- `windows-gha-buildtools.pkr.hcl`: heavier Windows runner template intended for VS Build Tools/MSBuild workloads.

## Notes

- Adapt ISO paths, storage names, bridge names, and credentials to your Proxmox host.
- Use example var files as a starting point.
- Do not commit real `*.pkrvars.hcl` or `*.auto.pkrvars.hcl` files.
- Runner registration should not be baked into a template.
- **Copy the autounattend template first.** `autounattend.xml` is gitignored because it
  holds the build/Administrator password; only `autounattend.xml.example` is committed.
  Before building: `cp autounattend.xml.example autounattend.xml`.
- **Build password must match in two places, and it sticks.** The `winrm_password` Packer
  var and the `<AdministratorPassword>`/auto-logon password in your local
  `autounattend.xml` are the same account, and that password becomes the **template's
  local Administrator password** — inherited by every cloned runner. Set a real,
  private password in both; `autounattend.xml` is a static `cd_files` ISO Packer cannot
  template, so the two must be edited to match or WinRM auth (and the build) fails.
- Templates build from a Windows Server **evaluation** ISO; the 180-day eval clock starts
  at build. See `../../docs/windows-runner.md` for regeneration/rearm.
