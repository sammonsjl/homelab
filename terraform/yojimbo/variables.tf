# tofu/variables.tf

variable "proxmox_token" {
  description = "Proxmox API Token ID, read from the .env_vars"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub token"
  sensitive   = true
  type        = string
  default     = ""
}

variable "github_org" {
  description = "GitHub organization"
  type        = string
  default     = ""
}

variable "github_repository" {
  description = "GitHub repository"
  type        = string
  default     = ""
}

variable "vault_token" {
  type        = string
  sensitive   = true
  description = "Vault token to be stored in the secret"
  default     = ""
}
