output "id" {
  value       = local.function_app_id
  description = "Specifies the resource id of the Web App"
}

output "name" {
  value       = one(concat(azurerm_linux_function_app.example[*].name, azurerm_function_app_flex_consumption.example[*].name))
  description = "Specifies the name of the Web App"
}

output "default_hostname" {
  value       = one(concat(azurerm_linux_function_app.example[*].default_hostname, azurerm_function_app_flex_consumption.example[*].default_hostname))
  description = "Specifies the default hostname of the Web App"
}

output "outbound_ip_addresses" {
  value       = one(concat(azurerm_linux_function_app.example[*].outbound_ip_addresses, azurerm_function_app_flex_consumption.example[*].outbound_ip_addresses))
  description = "Specifies the outbound IP addresses of the Web App"
}

output "principal_id" {
  value       = one(concat(azurerm_linux_function_app.example[*].identity[0].principal_id, azurerm_function_app_flex_consumption.example[*].identity[0].principal_id))
  description = "Specifies the Principal ID of the System Assigned Managed Identity"
}
