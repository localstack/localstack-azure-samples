output "id" {
  value       = azurerm_linux_web_app.example.id
  description = "Specifies the resource id of the Web App"
}

output "name" {
  value       = azurerm_linux_web_app.example.name
  description = "Specifies the name of the Web App"
}

output "default_hostname" {
  value       = azurerm_linux_web_app.example.default_hostname
  description = "Specifies the default hostname of the Web App"
}

output "outbound_ip_addresses" {
  value       = azurerm_linux_web_app.example.outbound_ip_addresses
  description = "Specifies the outbound IP addresses of the Web App"
}

output "principal_id" {
  value       = var.identity_type == "SystemAssigned" ? azurerm_linux_web_app.example.identity[0].principal_id : null
  description = "Specifies the principal id of the system-assigned managed identity, or null when the Web App uses a user-assigned identity (its principal id comes from the azurerm_user_assigned_identity resource)"
}
