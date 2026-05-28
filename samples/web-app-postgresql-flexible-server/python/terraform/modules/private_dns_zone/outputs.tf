output "name" {
  description = "Specifies the name of the private dns zone"
  value       = azurerm_private_dns_zone.example.name
}

output "id" {
  description = "Specifies the resource id of the private dns zone"
  value       = azurerm_private_dns_zone.example.id
}
