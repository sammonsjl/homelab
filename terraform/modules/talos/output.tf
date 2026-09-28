# tofu/talos/output.tf
output "client_configuration" {
  value     = module.cluster.client_configuration
  sensitive = true
}

output "kube_config" {
  value     = module.cluster.kube_config
  sensitive = true
}

output "machine_config" {
  value = module.cluster.machine_config
}
