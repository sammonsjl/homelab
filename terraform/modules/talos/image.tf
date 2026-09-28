# The node image, imported onto each Proxmox host. Which image (schematic and
# version) comes from ../talos-cluster, so it matches the install image the
# machine config points upgrades at.
resource "proxmox_virtual_environment_download_file" "this" {
  for_each = toset(distinct([for k, v in var.nodes : "${v.host_node}_${module.cluster.images[k].id}"]))

  node_name = split("_", each.key)[0]
  # "import" content lets the VM disk use import_from (API-based import,
  # PVE 8.2+) instead of file_id, which needs SSH access to the node
  content_type = "import"
  datastore_id = var.image.proxmox_datastore

  # import content can't decompress archives, so fetch the uncompressed qcow2
  file_name = "${var.cluster.name}-talos-${split("_", each.key)[1]}-${split("_", each.key)[2]}-${var.image.platform}-${var.image.arch}.qcow2"
  url       = "${var.image.factory_url}/image/${split("_", each.key)[1]}/${split("_", each.key)[2]}/${var.image.platform}-${var.image.arch}.qcow2"
  overwrite = false
}
