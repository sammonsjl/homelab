output "client_configuration" {
  value     = data.talos_client_configuration.this
  sensitive = true
}

output "kube_config" {
  value     = data.talos_cluster_kubeconfig.this
  sensitive = true
}

output "machine_config" {
  value = data.talos_machine_configuration.this
}

# What each node should boot, for the caller to fetch as a disk image:
# ${factory_url}/image/<schematic_id>/<version>/<platform>-<arch>.qcow2
output "images" {
  value = {
    for k, v in var.nodes : k => {
      schematic_id = v.update == true ? local.update_schematic_id : local.schematic_id
      version      = v.update == true ? local.update_version : local.version
      id           = "${v.update == true ? local.update_schematic_id : local.schematic_id}_${v.update == true ? local.update_version : local.version}"
      url          = "${var.image.factory_url}/image/${v.update == true ? local.update_schematic_id : local.schematic_id}/${v.update == true ? local.update_version : local.version}/${var.image.platform}-${var.image.arch}.qcow2"
    }
  }
}

# For authenticating service-account tokens without calling back into the
# API server (Vault JWT auth): the public half of the cluster's
# service-account signing key, and the issuer Talos stamps on the tokens.
data "tls_public_key" "service_account" {
  private_key_pem = base64decode(talos_machine_secrets.this.machine_secrets.certs.k8s_serviceaccount.key)
}

output "service_account_issuer" {
  value = "https://${var.cluster.endpoint}:6443"
}

output "service_account_public_key_pem" {
  value = data.tls_public_key.service_account.public_key_pem
}
