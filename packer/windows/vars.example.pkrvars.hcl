proxmox_url      = "https://pve.example.local:8006/api2/json"
proxmox_username = "packer@pve!packer"
proxmox_token    = "CHANGE_ME"
proxmox_node     = "pve"

iso_file     = "local:iso/windows-server-2022.iso"
storage_pool = "local-lvm"
# Storage for the generated build-time CD. Must allow ISO content. On a Ceph-only
# cluster point this at a CephFS storage (e.g. "cephfs"). See docs/deploy.md.
iso_storage_pool = "local"
bridge           = "vmbr0"
# virtio-win ISO — mounted so the QEMU guest agent installs at first boot (the builder
# needs it to discover the VM IP for WinRM). Upload virtio-win.iso to an iso storage.
virtio_iso = "local:iso/virtio-win.iso"

# Override locally if needed. Do not commit real local var files.
vm_name        = "tmpl-win-gha-core"
winrm_username = "Administrator"
winrm_password = "CHANGE_ME_BUILD_PASSWORD"
