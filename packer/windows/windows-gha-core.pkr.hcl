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

variable "virtio_iso" {
  type        = string
  default     = "cephfs:iso/virtio-win.iso"
  description = "virtio-win ISO volume. Mounted at build time: vioscsi is injected into WinPE for the boot disk, and the guest agent + remaining virtio drivers install at first boot."
}

variable "install_updates" {
  type        = bool
  default     = true
  description = "Run Windows Update during the build (adds significant time). Set false for fast test builds."
}

variable "runner_version" {
  default     = "2.335.1"
  description = "GitHub Actions runner version to bake (unregistered). Builder auto-bumps to latest."
}
variable "dotnet_channel" {
  default     = "10.0"
  description = ".NET SDK channel to bake (matches the dotnet10 label)."
}
variable "git_for_windows_url" {
  default     = "https://github.com/git-for-windows/git/releases/download/v2.51.0.windows.1/Git-2.51.0-64-bit.exe"
  description = "Git for Windows installer URL."
}

variable "cpu_type" {
  type        = string
  default     = "host"
  description = "Proxmox CPU type. 'host' exposes the full physical CPU (AES-NI/AVX) for best CI performance; the pinned non-HA fleet does not live-migrate, so passthrough is safe. Use a named model only if you need cross-CPU migration."
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
  os       = "win11"
  machine  = "q35"
  cpu_type = var.cpu_type
  cores    = 4
  sockets  = 1
  memory   = 8192

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

  # virtio-scsi boot disk. Works because autounattend injects the vioscsi driver into
  # WinPE (Microsoft-Windows-PnpCustomizationsWinPE DriverPaths) so Setup sees the disk.
  disks {
    type         = "scsi"
    disk_size    = "80G"
    storage_pool = var.storage_pool
    format       = "raw"
  }

  # virtio NIC. netkvm is installed at FirstLogon (pnputil) before enable-winrm, so the
  # network is up by the time the builder needs WinRM.
  network_adapters {
    model  = "virtio"
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

  # virtio-win ISO (existing storage volume). Provides the QEMU guest agent that the
  # installer runs at first boot so the builder can discover the VM IP for WinRM.
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

  # Windows Update (toggle with install_updates). The rgl/windows-update provisioner
  # handles the search/install/reboot loop until no updates remain.
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

  # Upload the JIT bootstrap + boot waiter, then bake the toolchain + runner + waiter task.
  provisioner "file" {
    source      = "../../orchestrator/bootstrap/windows-runner-once.ps1"
    destination = "C:/Windows/Temp/windows-runner-once.ps1"
  }
  provisioner "file" {
    source      = "../../orchestrator/bootstrap/gha-runner-waiter.ps1"
    destination = "C:/Windows/Temp/gha-runner-waiter.ps1"
  }
  provisioner "powershell" {
    environment_vars = [
      "RUNNER_VERSION=${var.runner_version}",
      "DOTNET_CHANNEL=${var.dotnet_channel}",
      "GIT_URL=${var.git_for_windows_url}",
    ]
    scripts = ["scripts/install-runner.ps1"]
  }

  # cleanup last — the proxmox-iso builder stops the VM itself once provisioning finishes.
  provisioner "powershell" {
    scripts = [
      "scripts/cleanup.ps1"
    ]
  }
}
