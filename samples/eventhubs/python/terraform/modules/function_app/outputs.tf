output "id" {
  value       = azurerm_linux_function_app.example.id
  description = "Specifies the resource id of the Function App"
}

output "name" {
  value       = azurerm_linux_function_app.example.name
  description = "Specifies the name of the Function App"
}

output "default_hostname" {
  value       = azurerm_linux_function_app.example.default_hostname
  description = "Specifies the default hostname of the Function App"
}

output "principal_id" {
  value       = var.identity_type == "SystemAssigned" ? azurerm_linux_function_app.example.identity[0].principal_id : null
  description = "Specifies the principal id of the system-assigned managed identity, or null when the Function App uses a user-assigned identity (its principal id comes from the managed_identity module)"
}
