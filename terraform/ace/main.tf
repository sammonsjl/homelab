# ACE control-plane VM (podman host). Terraform provisions the VM only;
# installing ACE on it is a separate step.

resource "proxmox_download_file" "cloud_image" {
  node_name    = var.host_node
  content_type = "iso"
  datastore_id = var.snippets_datastore_id
  url          = var.cloud_image_url
  # bpg only imports disk images named *.img/*.iso
  file_name = "ace-cloud-image.img"
}

# GenericCloud images ship without qemu-guest-agent; without it the VM
# resource hangs waiting on agent.enabled, so cloud-init must install it.
# The snippet is ignored by Proxmox unless the datastore has the Snippets
# content type enabled (Datacenter -> Storage -> local -> Content).
resource "proxmox_virtual_environment_file" "cloud_init" {
  node_name    = var.host_node
  content_type = "snippets"
  datastore_id = var.snippets_datastore_id

  source_raw {
    file_name = "ace-user-data.yaml"
    data      = <<-EOF
      #cloud-config
      hostname: ace
      users:
        - name: ${var.username}
          groups:
            - wheel
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.ssh_public_key}
      package_update: true
      packages:
        - qemu-guest-agent
      runcmd:
        - systemctl enable --now qemu-guest-agent
    EOF
  }
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

  # First boot blocks here until cloud-init finishes installing the agent
  agent {
    enabled = true
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
    file_id      = proxmox_download_file.cloud_image.id
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

    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
  }
}
