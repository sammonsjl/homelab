terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.9"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "1.9.6"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.12.0"
    }
  }
}

# The system instance; being in the `libvirt` group is enough.
provider "libvirt" {
  uri = "qemu:///system"
}

# The token comes from ~/.vault-token (or VAULT_TOKEN).
provider "vault" {
  address = "http://192.168.1.4:8200"
}

provider "flux" {
  kubernetes = {
    host                   = module.talos.kube_config.kubernetes_client_configuration.host
    client_certificate     = base64decode(module.talos.kube_config.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(module.talos.kube_config.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(module.talos.kube_config.kubernetes_client_configuration.ca_certificate)
  }
  git = {
    branch = "main"
    url    = "ssh://git@github.com/${var.github_org}/${var.github_repository}.git"
    ssh = {
      username    = "git"
      private_key = file(pathexpand("~/.ssh/id_rsa"))
    }
  }
}
