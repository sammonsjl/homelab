terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"
    }
  }
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
