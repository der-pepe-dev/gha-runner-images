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
variable "iso_storage_pool" {
  default     = "local"
  description = "Storage for the generated cidata CD (autoinstall user-data/meta-data). Must allow ISO content; on Ceph use a CephFS storage."
}
variable "bridge" { default = "vmbr0" }
variable "vm_name" { default = "tmpl-ubuntu-gha-core" }
variable "cpu_type" {
  default     = "host"
  description = "Proxmox CPU type. 'host' exposes the full physical CPU for best CI performance; safe for the pinned non-HA fleet."
}

variable "ssh_username" {
  default     = "ansible"
  description = "Build/provisioning user created by autoinstall (must match user-data identity.username)."
}
variable "ssh_password" {
  type        = string
  sensitive   = true
  default     = "ChangeMe_GHA_2026"
  description = "Build user password. MUST match the hashed password in cloud-init/user-data. Replace both for production."
}
variable "install_updates" {
  type        = bool
  default     = true
  description = "Run apt dist-upgrade during the build. Set false for fast test builds."
}
variable "runner_version" {
  default     = "2.335.1"
  description = "Pinned GitHub Actions runner version to bake into the image (unregistered)."
}

# CI toolchain baked into the image (ephemeral runners can't install per-job). Derived
# from docs/consumers.md; extend here + record the consumer row in the same change.
variable "runner_apt_packages" {
  default     = "build-essential cmake ninja-build mingw-w64 binutils gdb git curl wget unzip zip jq ca-certificates pkg-config sqlite3 ffmpeg python3 python3-pip python3-venv"
  description = "Space-separated apt packages installed into the runner image."
}
variable "dotnet_channel" {
  default     = "10.0"
  description = ".NET SDK channel to install (matches the dotnet10 runner label)."
}
variable "install_powershell" {
  type        = bool
  default     = true
  description = "Install PowerShell 7 (consumers.md lists it for all runners)."
}

source "proxmox-iso" "ubuntu_gha_core" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_name       = var.vm_name
  template_name = var.vm_name

  os       = "l26"
  machine  = "q35"
  cpu_type = var.cpu_type
  cores    = 2
  sockets  = 1
  memory   = 4096

  # Ubuntu has inbox virtio drivers, so virtio-scsi disk + virtio NIC + guest agent all
  # work with no driver injection (unlike Windows).
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true

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

  iso_file    = var.iso_file
  unmount_iso = true

  # NoCloud datasource: autoinstall reads user-data/meta-data from a CD labeled "cidata".
  additional_iso_files {
    device           = "sata1"
    iso_storage_pool = var.iso_storage_pool
    cd_files = [
      "cloud-init/user-data",
      "cloud-init/meta-data",
    ]
    cd_label = "cidata"
    unmount  = true
  }

  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "30m"

  boot_wait = "5s"

  # At the GRUB screen, drop to the command line and boot the casper kernel with
  # autoinstall + the NoCloud datasource (the cidata CD provides the data).
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>",
  ]
}

build {
  sources = ["source.proxmox-iso.ubuntu_gha_core"]

  # Patch the image (toggle with install_updates).
  dynamic "provisioner" {
    for_each = var.install_updates ? [1] : []
    labels   = ["shell"]
    content {
      inline = [
        "sudo apt-get update",
        "sudo DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade",
      ]
    }
  }

  # Bake the CI toolchain (ephemeral runners can't install per-job): apt packages +
  # .NET SDK + PowerShell from the Microsoft feed.
  provisioner "shell" {
    inline = [
      "curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -o /tmp/ms-prod.deb",
      "sudo dpkg -i /tmp/ms-prod.deb && rm -f /tmp/ms-prod.deb",
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ${var.runner_apt_packages} dotnet-sdk-${var.dotnet_channel}",
      "${var.install_powershell ? "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y powershell" : "true"}",
      "dotnet --version && cmake --version | head -1",
    ]
  }

  # Bake the GitHub Actions runner (UNREGISTERED) + the ephemeral waiter, so a cloned
  # slot only needs the orchestrator to inject /etc/gha-runner/env and boot.
  provisioner "file" {
    source      = "../../orchestrator/bootstrap/linux-runner-once.sh"
    destination = "/tmp/linux-runner-once.sh"
  }
  provisioner "file" {
    source      = "../../orchestrator/bootstrap/gha-runner-waiter.service"
    destination = "/tmp/gha-runner-waiter.service"
  }
  provisioner "shell" {
    inline = [
      "id gha-runner >/dev/null 2>&1 || sudo useradd -m -s /bin/bash gha-runner",
      "sudo mkdir -p /opt/actions-runner /opt/actions-work /opt/gha-runner /etc/gha-runner",
      "curl -fsSL -o /tmp/runner.tar.gz https://github.com/actions/runner/releases/download/v${var.runner_version}/actions-runner-linux-x64-${var.runner_version}.tar.gz",
      "sudo tar -xzf /tmp/runner.tar.gz -C /opt/actions-runner",
      "sudo /opt/actions-runner/bin/installdependencies.sh",
      "sudo install -m 0755 /tmp/linux-runner-once.sh /opt/gha-runner/linux-runner-once.sh",
      "sudo chown -R gha-runner:gha-runner /opt/actions-runner /opt/actions-work",
      "sudo install -m 0644 /tmp/gha-runner-waiter.service /etc/systemd/system/gha-runner-waiter.service",
      "sudo systemctl enable gha-runner-waiter.service",
    ]
  }

  # Generalize the image so clones get unique identity (machine-id, ssh host keys).
  provisioner "shell" {
    inline = [
      # Install a first-boot oneshot that regenerates SSH host keys before sshd if they
      # are missing. We can't rely on cloud-init for this on a clone (it may have no
      # datasource), and without host keys sshd resets every connection.
      "printf '%s\\n' '[Unit]' 'Description=Regenerate SSH host keys if missing' 'Before=ssh.service' 'ConditionPathExistsGlob=!/etc/ssh/ssh_host_*_key' '[Service]' 'Type=oneshot' 'ExecStart=/usr/bin/ssh-keygen -A' '[Install]' 'WantedBy=multi-user.target' | sudo tee /etc/systemd/system/regen-ssh-host-keys.service >/dev/null",
      "sudo systemctl enable regen-ssh-host-keys.service",
      # Now generalize: clones regenerate keys (via the oneshot) and a fresh machine-id.
      "sudo cloud-init clean --logs",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo apt-get -y autoremove --purge",
      "sudo apt-get clean",
    ]
  }
}
