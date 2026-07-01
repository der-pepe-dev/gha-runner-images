proxmox_url      = "https://pve.example.local:8006/api2/json"
proxmox_username = "packer@pve!packer"
proxmox_token    = "CHANGE_ME"
proxmox_node     = "pve"

iso_file     = "local:iso/ubuntu-24.04-live-server-amd64.iso"
storage_pool = "local-lvm"
# Storage for the generated cidata CD (autoinstall data). Must allow ISO content;
# on a Ceph-only cluster use a CephFS storage (e.g. "cephfs"). See docs/deploy.md.
iso_storage_pool = "local"
bridge           = "vmbr0"
vm_name          = "tmpl-ubuntu-gha-core"

# Build user. ssh_password MUST match the hashed password in cloud-init/user-data
# (placeholder "ChangeMe_GHA_2026"). Replace both for production. Never commit a real
# password: copy this to a gitignored *.pkrvars.hcl (or pass -var / PKR_VAR_ssh_password).
ssh_username = "ansible"
ssh_password = "ChangeMe_GHA_2026"
