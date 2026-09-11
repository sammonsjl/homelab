# tofu/talos/providers.tf
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.113.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">=0.5.0"
    }
  }
}
