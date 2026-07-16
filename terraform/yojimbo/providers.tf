# tofu/providers.tf
terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "1.9.2"
    }
    github = {
      source  = "integrations/github"
      version = ">= 6.1"
    }
  }
}

provider "flux" {
  kubernetes = {
    host                   = module.talos.kube_config.kubernetes_client_configuration.host
    client_certificate     = base64decode(module.talos.kube_config.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(module.talos.kube_config.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(module.talos.kube_config.kubernetes_client_configuration.ca_certificate)
  }
  git = {
    branch = "master"
    url    = "https://github.com/${var.github_org}/${var.github_repository}.git"
    http = {
      username = "git"
      password = var.github_token
    }
  }
}

provider "github" {
  owner = var.github_org
  token = var.github_token
}

provider "proxmox" {
  endpoint  = "https://192.168.1.3:8006"
  insecure  = true
  api_token = var.proxmox_token
  ssh {
    agent    = true
    username = "root"
  }
}
