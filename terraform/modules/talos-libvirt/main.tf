# Talos nodes on local KVM/libvirt. Everything Talos is ../talos-cluster,
# shared with ../talos (Proxmox), so a cluster built here gets the same
# machine config, image schematic and Cilium bootstrap as one built there.
#
# The domain settings that are not defaults (ACPI, a video device, the
# guest-agent channel) come from ace-containerized-installer/terraform/kvm,
# where each was found missing the hard way.

locals {
  prefix  = split("/", var.network.cidr)[1]
  gateway = cidrhost(var.network.cidr, 1)
  # Distinct images across the nodes (more than one only mid-upgrade).
  images = { for k, v in module.cluster.images : v.id => v.url... }
}

module "cluster" {
  source = "../talos-cluster"

  image = var.image
  cluster = {
    name          = var.cluster.name
    endpoint      = var.cluster.endpoint
    talos_version = var.cluster.talos_version
    region        = var.cluster.region
  }
  nodes = {
    for k, v in var.nodes : k => {
      machine_type = v.machine_type
      ip           = v.ip
      zone         = var.cluster.region
      update       = v.update
    }
  }
  node_instance_ids = { for k, v in libvirt_domain.node : k => v.id }
  cilium            = var.cilium
}

resource "libvirt_network" "this" {
  name      = var.network.name
  autostart = true
  forward   = { mode = "nat" }
  ips = [{
    address = local.gateway
    prefix  = tonumber(local.prefix)
  }]
  dns = { enable = "yes" }
}

resource "libvirt_pool" "this" {
  name   = var.pool.name
  type   = "dir"
  target = { path = var.pool.path }
  # qcow2 on btrfs fragments badly; libvirt sets the directory NOCOW where the
  # filesystem supports it and ignores it otherwise.
  features = { cow = { state = "no" } }
}

resource "libvirt_volume" "image" {
  for_each = local.images
  name     = "talos-${each.key}.qcow2"
  pool     = libvirt_pool.this.name
  target   = { format = { type = "qcow2" } }
  create   = { content = { url = each.value[0] } }
}

# Each node boots a copy-on-write overlay of the Talos image.
resource "libvirt_volume" "disk" {
  for_each = var.nodes
  name     = "${each.key}.qcow2"
  pool     = libvirt_pool.this.name
  capacity = each.value.disk_size_gb * 1024 * 1024 * 1024
  target   = { format = { type = "qcow2" } }
  backing_store = {
    path   = libvirt_volume.image[module.cluster.images[each.key].id].path
    format = { type = "qcow2" }
  }
}

# Talos boots into maintenance mode with only this: hostname and a static
# address. The machine config is applied over the API afterwards, exactly as
# on Proxmox (which writes the same two things into its own cloud-init drive).
resource "libvirt_cloudinit_disk" "node" {
  for_each = var.nodes
  name     = "${each.key}-cidata"
  meta_data = yamlencode({
    instance-id    = each.key
    local-hostname = each.key
  })
  user_data = ""
  network_config = yamlencode({
    version = 2
    ethernets = {
      eth0 = {
        match       = { macaddress = each.value.mac }
        addresses   = ["${each.value.ip}/${local.prefix}"]
        routes      = [{ to = "0.0.0.0/0", via = local.gateway }]
        nameservers = { addresses = [local.gateway] }
      }
    }
  })
}

resource "libvirt_volume" "cidata" {
  for_each = var.nodes
  name     = "${each.key}-cidata.iso"
  pool     = libvirt_pool.this.name
  create   = { content = { url = libvirt_cloudinit_disk.node[each.key].path } }
}

resource "libvirt_domain" "node" {
  for_each    = var.nodes
  name        = each.key
  type        = "kvm"
  description = each.value.machine_type == "controlplane" ? "Talos Control Plane" : "Talos Worker"
  memory      = each.value.memory_mb
  memory_unit = "MiB"
  vcpu        = each.value.cpu
  autostart   = true
  running     = true

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }
  cpu = { mode = "host-passthrough" }
  # Not defaults: without ACPI a q35 domain gets acpi=off and never leaves
  # the BIOS.
  features = {
    acpi = true
    apic = {}
  }

  devices = {
    # virtio-scsi, as Proxmox's virtio-scsi-single: the disk is /dev/sda, which
    # is what the install-image patch selects.
    controllers = [{ type = "scsi", model = "virtio-scsi" }]
    disks = [
      {
        source = { volume = { pool = libvirt_volume.disk[each.key].pool, volume = libvirt_volume.disk[each.key].name } }
        target = { bus = "scsi", dev = "sda" }
        driver = { type = "qcow2", discard = "unmap" }
      },
      {
        device = "cdrom"
        source = { volume = { pool = libvirt_volume.cidata[each.key].pool, volume = libvirt_volume.cidata[each.key].name } }
        target = { bus = "sata", dev = "sdb" }
      },
    ]
    interfaces = [{
      type   = "network"
      model  = { type = "virtio" }
      mac    = { address = each.value.mac }
      source = { network = { network = libvirt_network.this.name } }
    }]
    # `virsh console <node>`; everything it prints is also kept here (root-readable).
    consoles = [{
      target = { type = "serial", port = 0 }
      log    = { file = "/var/log/libvirt/qemu/${each.key}-console.log", append = "on" }
    }]
    # Needed even headless: with no video device the image hangs in the BIOS.
    videos = [{ model = { type = "virtio", heads = 1, primary = "yes" } }]
    rngs   = [{ model = "virtio", backend = { random = "/dev/urandom" } }]
    # For the qemu-guest-agent extension in the schematic.
    channels = [{
      source = { unix = { mode = "bind" } }
      target = { virt_io = { name = "org.qemu.guest_agent.0" } }
    }]
  }
}
