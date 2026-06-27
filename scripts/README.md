# Scripts

Helper scripts for local setup and Proxmox runner fleet scaffolding.

These scripts are intentionally examples. They use placeholders and environment variables rather than committed secrets.

## Main files

- `discover-proxmox.sh` - connects to the Proxmox API and fills the gitignored
  `packer/{windows,linux}/local.pkrvars.hcl` with detected storage_pool (prefers Ceph
  rbd), iso_storage_pool (prefers cephfs), iso_file, bridge, and node. Secrets via
  `PROXMOX_TOKEN_ID`/`PROXMOX_TOKEN`; run before the first `packer build`. See
  `../docs/deploy.md`.
- `clone-proxmox-template.ps1` - minimal example for cloning one Proxmox template.
- `clone-runner-fleet.ps1` - example for cloning the default runner fleet.
- `fleet.example.yml` - example fleet layout with one local orchestrator and two runners per Proxmox node.
- `get-runner-token.ps1` - helper to request a GitHub runner registration token.

For ongoing ephemeral runner reset/recreate logic, see `../orchestrator/`.
