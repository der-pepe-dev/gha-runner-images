packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.3"
    }
  }
}

variable "proxmox_url" { type = string }
variable "proxmox_username" { type = string }
variable "proxmox_token" {
  type      = string
  sensitive = true
}
variable "proxmox_node" { default = "pve" }
variable "iso_file" { default = "local:iso/windows-server-2022.iso" }
variable "storage_pool" { default = "local-lvm" }
variable "iso_storage_pool" {
  default     = "local"
  description = "Storage for the generated build-time CD (autounattend + scripts). Must allow ISO content; on a Ceph-only cluster use a CephFS storage."
}
variable "bridge" { default = "vmbr0" }
variable "vm_name" { default = "tmpl-win-gha-buildtools" }
variable "winrm_username" { default = "Administrator" }
variable "winrm_password" {
  type      = string
  sensitive = true
  default   = "CHANGE_ME_BUILD_PASSWORD"
}

source "proxmox-iso" "win_gha_buildtools" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_name       = var.vm_name
  template_name = var.vm_name

  os      = "win11"
  machine = "q35"
  cores   = 6
  sockets = 1
  memory  = 16384

  # UEFI (OVMF) — autounattend.xml uses a GPT layout; see windows-gha-core for details.
  bios = "ovmf"
  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  scsi_controller = "virtio-scsi-single"

  # SATA boot disk so Windows Setup sees it without virtio drivers; see
  # windows-gha-core for details.
  disks {
    type         = "sata"
    disk_size    = "128G"
    storage_pool = var.storage_pool
    format       = "raw"
  }

  # e1000 NIC so Windows has network without virtio drivers; see windows-gha-core.
  network_adapters {
    model  = "e1000"
    bridge = var.bridge
  }

  iso_file    = var.iso_file
  unmount_iso = true

  additional_iso_files {
    device           = "sata3"
    iso_storage_pool = var.iso_storage_pool
    cd_files = [
      "autounattend.xml",
      "scripts/enable-winrm.ps1",
      "scripts/install-qemu-guest-agent.ps1",
      "scripts/cleanup.ps1"
    ]
    cd_label = "gha_build"
  }

  communicator   = "winrm"
  winrm_username = var.winrm_username
  winrm_password = var.winrm_password
  winrm_timeout  = "8h"

  boot_wait = "3s"

  # Spam <enter> to get past the UEFI "Press any key to boot from CD..." prompt;
  # see windows-gha-core for details.
  boot_command = [
    "<enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter>",
    "<wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter>"
  ]

  # The proxmox-iso builder stops the VM itself once provisioning finishes (it has no
  # shutdown_command field), so cleanup.ps1 runs as the last provisioner and must NOT
  # power the VM off.
}

build {
  sources = ["source.proxmox-iso.win_gha_buildtools"]

  provisioner "powershell" {
    scripts = [
      "scripts/install-qemu-guest-agent.ps1",
      "scripts/cleanup.ps1"
    ]
  }

  # Visual Studio Build Tools are normally installed by Ansible using
  # ansible/playbooks/windows-buildtools.yml. Install them here only if you
  # intentionally want them baked into the image at Packer build time.
}
