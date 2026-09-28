# The Image Factory schematic IDs for the node images. The caller turns these
# into its own disk images (outputs.images); the install-image patch in
# config.tf points upgrades at the same schematic and version.
locals {
  version      = var.image.version
  schematic_id = jsondecode(data.http.schematic_id.response_body)["id"]

  update_version      = coalesce(var.image.update_version, var.image.version)
  update_schematic    = coalesce(var.image.update_schematic, var.image.schematic)
  update_schematic_id = jsondecode(data.http.updated_schematic_id.response_body)["id"]
}

data "http" "schematic_id" {
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = var.image.schematic
}

data "http" "updated_schematic_id" {
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = local.update_schematic
}
