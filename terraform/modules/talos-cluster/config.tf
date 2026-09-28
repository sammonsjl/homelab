# The Talos side of a cluster: secrets, machine configuration, apply,
# bootstrap, health and kubeconfig. Hypervisor-agnostic -- ../talos (Proxmox)
# and ../talos-libvirt (local KVM) build the VMs and call this with them, so
# yojimbo and bahamut get the same machine config from the same templates.
resource "talos_machine_secrets" "this" {
  talos_version = var.cluster.talos_version
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for k, v in var.nodes : v.ip]
  endpoints            = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"]
}

data "talos_machine_configuration" "this" {
  for_each         = var.nodes
  cluster_name     = var.cluster.name
  cluster_endpoint = "https://${var.cluster.endpoint}:6443"
  talos_version    = var.cluster.talos_version
  machine_type     = each.value.machine_type
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = each.value.machine_type == "controlplane" ? [
    templatefile("${path.module}/machine-config/control-plane.yaml.tftpl", {
      hostname       = each.key
      node_name      = each.value.zone
      cluster_name   = var.cluster.region
      cilium_values  = var.cilium.values
      cilium_install = var.cilium.install
    }),
    local.install_image_patch[each.key],
    ] : [
    templatefile("${path.module}/machine-config/worker.yaml.tftpl", {
      hostname     = each.key
      node_name    = each.value.zone
      cluster_name = var.cluster.region
    }),
    local.install_image_patch[each.key],
  ]
}

# The installer a later `talosctl upgrade` falls back to. Left unset, Talos
# writes the plain installer for the provider's SDK version -- no extensions --
# so an upgrade without --image would quietly drop iscsi-tools and with it
# every iSCSI volume. Same schematic and version the node was built from.
# Talos 1.14 keeps it in the UnattendedInstallConfig document and rejects
# machine.install.image alongside it. A patch replaces that document whole, so
# the disk selector Talos generates has to be restated with it.
locals {
  install_image_patch = {
    for k, v in var.nodes : k => yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer = {
        # <platform>-installer: plain "installer" is the metal one, and an
        # upgrade with it would move a nocloud VM off its platform.
        image = format("%s/%s-installer/%s:%s",
          replace(var.image.factory_url, "/^https?:\\/\\//", ""),
          var.image.platform,
          v.update == true ? local.update_schematic_id : local.schematic_id,
          v.update == true ? local.update_version : local.version,
        )
      }
      provisioning = {
        diskSelector = {
          match = "disk.dev_path == \"${v.install_disk}\""
        }
      }
    })
  }
}

# One per node, holding the ID of the VM the caller built for it.
# replace_triggered_by can only name a resource, not a variable, so this is
# what carries "the VM was replaced" into this module.
resource "terraform_data" "node" {
  for_each = var.nodes
  input    = var.node_instance_ids[each.key]
}

resource "talos_machine_configuration_apply" "this" {
  depends_on                  = [terraform_data.node]
  for_each                    = var.nodes
  node                        = each.value.ip
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  lifecycle {
    # re-run config apply if vm changes
    replace_triggered_by = [terraform_data.node[each.key]]
  }
}

resource "talos_machine_bootstrap" "this" {
  # Without this, bootstrap depends only on machine_secrets, so terraform
  # starts it in parallel with the image download and VM creation — it then
  # spins for its whole timeout against nodes that do not exist yet. Bootstrap
  # is only meaningful once a node has its configuration.
  depends_on = [talos_machine_configuration_apply.this]

  node                 = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"][0]
  endpoint             = var.cluster.endpoint
  client_configuration = talos_machine_secrets.this.client_configuration
}

data "talos_cluster_health" "this" {
  depends_on = [
    talos_machine_configuration_apply.this,
    talos_machine_bootstrap.this
  ]
  client_configuration = data.talos_client_configuration.this.client_configuration
  control_plane_nodes  = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"]
  worker_nodes         = [for k, v in var.nodes : v.ip if v.machine_type == "worker"]
  endpoints            = data.talos_client_configuration.this.endpoints
  timeouts = {
    read = "10m"
  }
}

data "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this,
    data.talos_cluster_health.this
  ]
  node                 = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"][0]
  endpoint             = var.cluster.endpoint
  client_configuration = talos_machine_secrets.this.client_configuration
  timeouts = {
    read = "1m"
  }
}
