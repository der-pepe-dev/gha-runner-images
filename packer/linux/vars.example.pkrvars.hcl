proxmox_url      = "https://pve.example.local:8006/api2/json"
proxmox_username = "packer@pve!packer"
proxmox_token    = "CHANGE_ME"
proxmox_node     = "pve"

iso_file     = "local:iso/ubuntu-24.04-live-server-amd64.iso"
storage_pool = "local-lvm"
bridge       = "vmbr0"
vm_name      = "tmpl-ubuntu-gha-core"
