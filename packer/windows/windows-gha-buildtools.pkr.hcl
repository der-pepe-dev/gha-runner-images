packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.3"
    }
    windows-update = {
      source  = "github.com/rgl/windows-update"
      version = ">= 0.14.1"
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
variable "virtio_iso" {
  default     = "cephfs:iso/virtio-win.iso"
  description = "virtio-win ISO volume; vioscsi injected into WinPE for the boot disk, guest agent + remaining drivers install at first boot."
}
variable "install_updates" {
  type        = bool
  default     = true
  description = "Run Windows Update during the build (adds significant time). Set false for fast test builds."
}
variable "cpu_type" {
  default     = "host"
  description = "Proxmox CPU type. 'host' exposes the full physical CPU (AES-NI/AVX) for best CI performance; safe for the pinned non-HA fleet."
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

  os       = "win11"
  machine  = "q35"
  cpu_type = var.cpu_type
  cores    = 6
  sockets  = 1
  memory   = 16384

  # UEFI (OVMF) — autounattend.xml uses a GPT layout; see windows-gha-core for details.
  bios = "ovmf"
  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  scsi_controller = "virtio-scsi-single"

  # virtio-scsi boot disk (vioscsi injected into WinPE via autounattend); see
  # windows-gha-core for details.
  disks {
    type         = "scsi"
    disk_size    = "128G"
    storage_pool = var.storage_pool
    format       = "raw"
  }

  # virtio NIC (netkvm installed at FirstLogon before WinRM); see windows-gha-core.
  network_adapters {
    model  = "virtio"
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

  # virtio-win ISO so the QEMU guest agent installs at first boot; see windows-gha-core.
  additional_iso_files {
    device   = "sata4"
    iso_file = var.virtio_iso
    unmount  = true
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

  # Windows Update (toggle with install_updates); see windows-gha-core.
  dynamic "provisioner" {
    for_each = var.install_updates ? [1] : []
    labels   = ["windows-update"]
    content {
      search_criteria = "IsInstalled=0"
      filters = [
        "exclude:$_.Title -like '*Preview*'",
        # Defender AV definitions change daily and auto-update on the runner — baking
        # them is pure waste (and they are large).
        "exclude:$_.Title -like '*Defender*'",
        "include:$true",
      ]
    }
  }

  # Guest agent + virtio drivers install at FirstLogon (autounattend); only cleanup
  # runs here. See windows-gha-core.
  provisioner "powershell" {
    scripts = [
      "scripts/cleanup.ps1"
    ]
  }

  # Visual Studio Build Tools are normally installed by Ansible using
  # ansible/playbooks/windows-buildtools.yml. Install them here only if you
  # intentionally want them baked into the image at Packer build time.
}
