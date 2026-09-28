# Bahamut: the dev cluster, on the laptop's KVM. Built from the same Talos
# module, machine-config templates, image schematic and Cilium bootstrap as
# yojimbo (../yojimbo), so a Talos change is tried here first: bump
# talos_version/image.version below, apply or `talosctl upgrade`, verify, and
# only then do the same in ../yojimbo.
#
# Three schedulable control planes, like yojimbo, so etcd quorum and rolling
# upgrades behave as they will in prod -- sized for a 16 GB laptop.
module "talos" {
  source = "../modules/talos-libvirt"

  image = {
    version   = "v1.14.1"
    schematic = file("${path.module}/../modules/talos-cluster/image/schematic.yaml")
  }
  cilium = {
    install = file("${path.module}/../modules/talos-cluster/inline-manifests/cilium-install.yaml")
    values  = file("${path.module}/../../infrastructure/controllers/base/cilium/values.yaml")
  }
  cluster = {
    name          = "bahamut"
    endpoint      = "192.168.150.20"
    talos_version = "v1.14.1"
    region        = "laptop"
  }
  # 192.168.150.100-150 is Cilium's LoadBalancer pool
  # (infrastructure/configs/bahamut/cilium/ip-pool.yaml).
  network = {
    name = "bahamut"
    cidr = "192.168.150.0/24"
  }
  pool = {
    name = "bahamut"
    path = "/var/lib/libvirt/images/bahamut"
  }
  nodes = {
    "bahamut-ctrl-00" = {
      machine_type = "controlplane"
      ip           = "192.168.150.20"
      mac          = "52:54:00:ba:0a:20"
      cpu          = 2
      memory_mb    = 3072
    }
    "bahamut-ctrl-01" = {
      machine_type = "controlplane"
      ip           = "192.168.150.21"
      mac          = "52:54:00:ba:0a:21"
      cpu          = 2
      memory_mb    = 3072
    }
    "bahamut-ctrl-02" = {
      machine_type = "controlplane"
      ip           = "192.168.150.22"
      mac          = "52:54:00:ba:0a:22"
      cpu          = 2
      memory_mb    = 3072
    }
  }
}

resource "flux_bootstrap_git" "this" {
  depends_on           = [module.talos]
  delete_git_manifests = false
  path                 = "clusters/bahamut"
}
