# tofu/providers.tf
terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.8.1"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.82.1"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox.endpoint
  insecure = var.proxmox.insecure

  api_token = var.proxmox.api_token
  ssh {
    agent    = true
    username = var.proxmox.username
  }
}
