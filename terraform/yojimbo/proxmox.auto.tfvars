# tofu/proxmox.auto.tfvars
proxmox = {
  name         = "lud"
  cluster_name = "homelab"
  endpoint     = "https://192.168.1.3:8006"
  insecure     = true
  username     = "root"
}
