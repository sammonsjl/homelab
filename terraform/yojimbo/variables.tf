# tofu/variables.tf

variable "proxmox_token" {
  description = "Proxmox API Token ID, read from the .env_vars"
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "GitHub organization"
  type        = string
  default     = "sammonsjl"
}

variable "github_repository" {
  description = "GitHub repository"
  type        = string
  default     = "homelab"
}
