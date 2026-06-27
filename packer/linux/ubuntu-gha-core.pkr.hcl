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

  # Generalize the image so clones get unique identity (machine-id, ssh host keys).
  provisioner "shell" {
    inline = [
      "sudo cloud-init clean --logs",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo apt-get -y autoremove --purge",
      "sudo apt-get clean",
    ]
  }
}
