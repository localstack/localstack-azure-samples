output "name" {
  description = "Specifies the name of the network security group"
  value       = azurerm_network_security_group.example.name
}

output "id" {
  description = "Specifies the resource id of the network security group"
  value       = azurerm_network_security_group.example.id
}
