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

output "service_account_issuer" {
  value = module.cluster.service_account_issuer
}

output "service_account_public_key_pem" {
  value = module.cluster.service_account_public_key_pem
}
