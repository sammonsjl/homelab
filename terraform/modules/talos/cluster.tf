# Proxmox builds the VMs; everything Talos is ../talos-cluster, shared with
# ../talos-libvirt.
module "cluster" {
  source = "../talos-cluster"

  image = {
    factory_url      = var.image.factory_url
    schematic        = var.image.schematic
    version          = var.image.version
    update_schematic = var.image.update_schematic
    update_version   = var.image.update_version
    arch             = var.image.arch
    platform         = var.image.platform
  }
  cluster = {
    name          = var.cluster.name
    endpoint      = var.cluster.endpoint
    talos_version = var.cluster.talos_version
    region        = var.cluster.proxmox_cluster
  }
  nodes = {
    for k, v in var.nodes : k => {
      machine_type = v.machine_type
      ip           = v.ip
      zone         = v.host_node
      update       = v.update
    }
  }
  node_instance_ids = { for k, v in proxmox_virtual_environment_vm.this : k => v.id }
  cilium            = var.cilium
}

# The Talos resources lived in this module before the split.
moved {
  from = talos_machine_secrets.this
  to   = module.cluster.talos_machine_secrets.this
}

moved {
  from = talos_machine_configuration_apply.this
  to   = module.cluster.talos_machine_configuration_apply.this
}

moved {
  from = talos_machine_bootstrap.this
  to   = module.cluster.talos_machine_bootstrap.this
}
