variable "proxmox_token" {
  description = "Proxmox API Token ID, read from the .env_vars"
  type        = string
  sensitive   = true
}

variable "cloud_image_url" {
  description = "Cloud image for the ACE control-plane VM. RHEL 9 is a drop-in swap but requires a developer-subscription manual download (plus subscription-manager in cloud-init); the ACE installer was proven on Rocky 9."
  type        = string
  default     = "https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
}

variable "host_node" {
  description = "Proxmox node to run the VM on"
  type        = string
  default     = "lud"
}

variable "vm_id" {
  type    = number
  default = 200
}

variable "ip_address" {
  description = "Static IPv4 address in CIDR notation"
  type        = string
  default     = "192.168.1.40/24"
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "cpu_cores" {
  type    = number
  default = 4
}

variable "memory_mb" {
  type    = number
  default = 8192
}

variable "disk_size_gb" {
  type    = number
  default = 60
}

variable "datastore_id" {
  description = "Datastore for the VM disk and cloud-init drive"
  type        = string
  default     = "local-lvm"
}

variable "image_datastore_id" {
  description = "Datastore holding the downloaded cloud image (must have the Import content type enabled)"
  type        = string
  default     = "local"
}

variable "username" {
  description = "Admin user created by cloud-init"
  type        = string
  default     = "jamie"
}

variable "ssh_public_key" {
  description = "SSH public key for the admin user"
  type        = string
}
