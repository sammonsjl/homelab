output "ip_address" {
  description = "ACE control-plane VM address"
  value       = split("/", var.ip_address)[0]
}
