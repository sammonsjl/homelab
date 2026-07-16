# tofu/main.tf
module "talos" {
  source = "../modules/talos"

  providers = {
    proxmox = proxmox
  }

  image = {
    version   = "v1.13.6"
    schematic = file("${path.module}/../modules/talos/image/schematic.yaml")
  }

  cilium = {
    install = file("${path.module}/../modules/talos/inline-manifests/cilium-install.yaml")
    values  = file("${path.module}/../../infrastructure/controllers/base/cilium/values.yaml")
  }

  cluster = {
    name            = "odin"
    endpoint        = "192.168.1.15"
    gateway         = "192.168.1.1"
    talos_version   = "v1.13.6"
    proxmox_cluster = "homelab"
  }

  nodes = {
    "odin-ctrl-00" = {
      host_node     = "lud"
      machine_type  = "controlplane"
      ip            = "192.168.1.15"
      mac_address   = "BC:24:11:2E:C8:00"
      vm_id         = 100
      cpu           = 8
      ram_dedicated = 4096
    }
    "odin-work-00" = {
      host_node     = "lud"
      machine_type  = "worker"
      ip            = "192.168.1.18"
      mac_address   = "BC:24:11:2E:C8:03"
      vm_id         = 103
      cpu           = 8
      ram_dedicated = 4096
    }
  }
}

resource "flux_bootstrap_git" "this" {
  depends_on           = [module.talos]
  delete_git_manifests = false
  path                 = "clusters/odin"
}
