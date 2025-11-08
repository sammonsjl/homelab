# tofu/main.tf
module "talos" {
  source = "../modules/talos"

  providers = {
    proxmox = proxmox
  }

  image = {
    version   = "v1.11.0"
    schematic = file("${path.module}/../modules/talos/image/schematic.yaml")
  }

  cilium = {
    install = file("${path.module}/../modules/talos/inline-manifests/cilium-install.yaml")
    values  = file("${path.module}/../../infrastructure/controllers/base/cilium/values.yaml")
  }

  cluster = {
    name            = "yojimbo"
    endpoint        = "192.168.1.20"
    gateway         = "192.168.1.1"
    talos_version   = "v1.11"
    proxmox_cluster = "homelab"
  }

  nodes = {
    "yojimbo-ctrl-00" = {
      host_node     = "lud"
      machine_type  = "controlplane"
      ip            = "192.168.1.20"
      mac_address   = "BC:24:11:2E:C8:04"
      vm_id         = 105
      cpu           = 8
      ram_dedicated = 6144
    }
    "yojimbo-ctrl-01" = {
      host_node     = "lud"
      machine_type  = "controlplane"
      ip            = "192.168.1.21"
      mac_address   = "BC:24:11:2E:C8:05"
      vm_id         = 106
      cpu           = 8
      ram_dedicated = 6144
      igpu          = false
    }
    "yojimbo-ctrl-02" = {
      host_node     = "lud"
      machine_type  = "controlplane"
      ip            = "192.168.1.22"
      mac_address   = "BC:24:11:2E:C8:06"
      vm_id         = 107
      cpu           = 4
      ram_dedicated = 6144
    }
    "yojimbo-work-00" = {
      host_node     = "lud"
      machine_type  = "worker"
      ip            = "192.168.1.23"
      mac_address   = "BC:24:11:2E:C8:07"
      vm_id         = 108
      cpu           = 8
      ram_dedicated = 6144
      igpu          = false
    }
  }
}

resource "flux_bootstrap_git" "this" {
  depends_on           = [module.talos]
  delete_git_manifests = false
  path                 = "clusters/yojimbo"
}

resource "kubernetes_namespace" "external_secrets" {
  depends_on = [module.talos]
  metadata {
    name = "external-secrets"
  }
}

resource "kubernetes_secret" "vault_token" {
  depends_on = [kubernetes_namespace.external_secrets]
  metadata {
    name      = "vault-token"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
  }

  type = "Opaque"

  data = {
    token = var.vault_token
  }
}
