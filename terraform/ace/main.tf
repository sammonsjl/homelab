# ACE control-plane VM (podman host). Terraform provisions the VM only;
# installing ACE on it is a separate step.

# "import" content + import_from below keep everything API-only; file_id
# and snippet uploads both require SSH access to the Proxmox node
resource "proxmox_download_file" "cloud_image" {
  node_name    = var.host_node
  content_type = "import"
  datastore_id = var.image_datastore_id
  url          = var.cloud_image_url
  file_name    = "ace-cloud-image.qcow2"
}

resource "proxmox_virtual_environment_vm" "ace" {
  node_name = var.host_node

  name        = "ace"
  description = "ACE Control Plane"
  tags        = ["ace", "control-plane"]
  on_boot     = true
  vm_id       = var.vm_id

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "seabios"

  # GenericCloud images ship without qemu-guest-agent and the API-generated
  # cloud-init (user_account) can't install packages; enabling the agent here
  # would hang the apply. Install qemu-guest-agent over SSH after first boot,
  # then flip this on.
  agent {
    enabled = false
  }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    ssd          = true
    size         = var.disk_size_gb
    import_from  = proxmox_download_file.cloud_image.id
  }

  boot_order = ["scsi0"]

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    user_account {
      username = var.username
      keys     = [var.ssh_public_key]
    }
  }
}
