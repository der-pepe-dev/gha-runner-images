packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.3"
    }
  }
}

variable "proxmox_url" {}
variable "proxmox_username" {}
variable "proxmox_token" {
  type      = string
  sensitive = true
}
variable "proxmox_node" { default = "pve" }
variable "iso_file" { default = "local:iso/ubuntu-24.04-live-server-amd64.iso" }
variable "storage_pool" { default = "local-lvm" }
variable "bridge" { default = "vmbr0" }
variable "vm_name" { default = "tmpl-ubuntu-gha-core" }

source "proxmox-iso" "ubuntu_gha_core" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_name       = var.vm_name
  template_name = var.vm_name

  os      = "l26"
  machine = "q35"
  cores   = 2
  sockets = 1
  memory  = 4096

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    disk_size    = "40G"
    storage_pool = var.storage_pool
    format       = "raw"
  }

  network_adapters {
    model  = "virtio"
    bridge = var.bridge
  }

  iso_file = var.iso_file

  # This is a skeleton. Add Ubuntu autoinstall boot command and cloud-init media
  # for a fully automated build.
}
