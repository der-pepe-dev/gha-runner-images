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
