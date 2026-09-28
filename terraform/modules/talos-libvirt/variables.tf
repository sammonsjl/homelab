variable "image" {
  description = "Talos image configuration, as for ../talos-cluster"
  type = object({
    factory_url      = optional(string, "https://factory.talos.dev")
    schematic        = string
    version          = string
    update_schematic = optional(string)
    update_version   = optional(string)
    arch             = optional(string, "amd64")
    platform         = optional(string, "nocloud")
  })
}

variable "cluster" {
  description = "Cluster configuration"
  type = object({
    name          = string
    endpoint      = string
    talos_version = string
    region        = string
  })
}

# Its own NAT network: the nodes and the Cilium LoadBalancer pool are
# reachable from this host only, and the cluster reaches out (NAS, Vault,
# registries) through the host's masquerade.
variable "network" {
  type = object({
    name = string
    cidr = string
  })
}

variable "pool" {
  type = object({
    name = string
    path = string
  })
}

variable "nodes" {
  description = "Cluster nodes, keyed by hostname"
  type = map(object({
    machine_type = string
    ip           = string
    # Fixed so cloud-init's network-config can match the NIC by it.
    mac          = string
    cpu          = number
    memory_mb    = number
    disk_size_gb = optional(number, 20)
    update       = optional(bool, false)
  }))
}

variable "cilium" {
  type = object({
    values  = string
    install = string
  })
}
