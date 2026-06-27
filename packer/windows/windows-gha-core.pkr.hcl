packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.3"
    }
  }
}

variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL, for example https://pve.example.local:8006/api2/json"
}

variable "proxmox_username" {
  type        = string
  description = "Proxmox API token username, for example packer@pve!packer"
}

variable "proxmox_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret. Do not commit real values."
}

variable "proxmox_node" {
  type        = string
  default     = "pve"
  description = "Target Proxmox node."
}

variable "iso_file" {
  type        = string
  default     = "local:iso/windows-server-2022.iso"
  description = "Windows Server ISO path in Proxmox storage."
}

variable "storage_pool" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage pool for VM disk."
}

variable "iso_storage_pool" {
  type        = string
  default     = "local"
  description = "Storage for the generated build-time CD (autounattend + scripts). Must allow ISO content; on a Ceph-only cluster use a CephFS storage."
}

variable "bridge" {
  type        = string
  default     = "vmbr0"
  description = "Proxmox network bridge."
}

variable "vm_name" {
  type        = string
  default     = "tmpl-win-gha-core"
  description = "Template VM name."
}

variable "winrm_username" {
  type        = string
  default     = "Administrator"
  description = "Temporary build-time Windows administrator user."
}

variable "winrm_password" {
  type        = string
  sensitive   = true
  default     = "CHANGE_ME_BUILD_PASSWORD"
  description = "Temporary build-time administrator password. Replace locally and do not commit."
}

source "proxmox-iso" "win_gha_core" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_name       = var.vm_name
  template_name = var.vm_name

  # Adjust to your environment if needed.
  os      = "win11"
  machine = "q35"
  cores   = 4
  sockets = 1
  memory  = 8192

  # UEFI (OVMF) — autounattend.xml uses a GPT layout (EFI/MSR/WinRE partitions), which
  # only applies under UEFI. Without this the VM boots legacy SeaBIOS and Windows Setup
  # fails to apply <DiskConfiguration>.
  bios = "ovmf"
  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  scsi_controller = "virtio-scsi-single"

  # SATA boot disk: Windows Setup (WinPE) has the inbox AHCI driver but NOT the
  # virtio-scsi driver, so a scsi/virtio disk is invisible during install and
  # <DiskConfiguration> fails. SATA installs with no driver injection. (For virtio
  # performance later, mount the virtio-win ISO and add a WinPE DriverPaths entry.)
  disks {
    type         = "sata"
    disk_size    = "80G"
    storage_pool = var.storage_pool
    format       = "raw"
  }

  # e1000: Windows has an inbox Intel E1000 driver, but not the virtio NetKVM driver,
  # so a virtio NIC would have no network after a clean install and WinRM could never
  # connect. e1000 works driver-free. (Switch to virtio + NetKVM later for throughput.)
  network_adapters {
    model  = "e1000"
    bridge = var.bridge
  }

  iso_file    = var.iso_file
  unmount_iso = true

  # Mount unattended install and build-time scripts.
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

  # The Windows ISO shows "Press any key to boot from CD or DVD..." under UEFI and waits
  # only ~5s. Spam <enter> across that window so the VM boots the installer instead of
  # falling through to the empty disk.
  boot_command = [
    "<enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter>",
    "<wait1><enter><wait1><enter><wait1><enter><wait1><enter><wait1><enter>"
  ]

  # Packer connects over WinRM after autounattend enables it. The proxmox-iso builder
  # stops the VM itself once provisioning finishes (it has no shutdown_command field),
  # so cleanup.ps1 runs as the last provisioner and must NOT power the VM off.
}

build {
  sources = ["source.proxmox-iso.win_gha_core"]

  provisioner "powershell" {
    scripts = [
      "scripts/install-qemu-guest-agent.ps1",
      "scripts/cleanup.ps1"
    ]
  }
}
