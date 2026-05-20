output "id" {
  value       = azurerm_linux_function_app.example.id
  description = "Specifies the resource id of the Web App"
}

output "name" {
  value       = azurerm_linux_function_app.example.name
  description = "Specifies the name of the Web App"
}

output "default_hostname" {
  value       = azurerm_linux_function_app.example.default_hostname
  description = "Specifies the default hostname of the Web App"
}

output "outbound_ip_addresses" {
  value       = azurerm_linux_function_app.example.outbound_ip_addresses
  description = "Specifies the outbound IP addresses of the Web App"
}

output "principal_id" {
  value       = azurerm_linux_function_app.example.identity[0].principal_id
  description = "Specifies the Principal ID of the System Assigned Managed Identity"
}
