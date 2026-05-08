output "name" {
  description = "Specifies the name of the container registry."
  value       = azurerm_container_registry.example.name
}

output "id" {
  description = "Specifies the resource id of the container registry."
  value       = azurerm_container_registry.example.id
}

output "resource_group_name" {
  description = "Specifies the name of the resource group."
  value       = var.resource_group_name
}

output "login_server" {
  description = "Specifies the login server of the container registry."
  value       = azurerm_container_registry.example.login_server
}

output "login_server_url" {
  description = "Specifies the login server url of the container registry."
  value       = "https://${azurerm_container_registry.example.login_server}"
}

output "admin_username" {
  description = "Specifies the admin username of the container registry."
  value       = azurerm_container_registry.example.admin_username
}

output "admin_password" {
  description = "Specifies the admin password of the container registry."
  value       = azurerm_container_registry.example.admin_password
}