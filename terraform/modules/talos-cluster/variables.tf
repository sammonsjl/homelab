variable "image" {
  description = "Talos image configuration"
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
    # topology.kubernetes.io/region on every node
    region = string
  })
}

variable "nodes" {
  description = "Cluster nodes, keyed by hostname"
  type = map(object({
    machine_type = string
    ip           = string
    # topology.kubernetes.io/zone -- the hypervisor host the node runs on
    zone   = string
    update = optional(bool, false)
    # The disk the install-image patch selects. /dev/sda on both hypervisors:
    # each gives the node a virtio-scsi disk.
    install_disk = optional(string, "/dev/sda")
  }))
}

variable "node_instance_ids" {
  description = "The ID of the VM backing each node, keyed like nodes. A changed ID re-applies that node's config."
  type        = map(string)
}

variable "cilium" {
  description = "Cilium configuration"
  type = object({
    values  = string
    install = string
  })
}
