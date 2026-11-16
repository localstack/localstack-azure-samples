output "name" {
  value       = azurerm_application_insights.example.name
  description = "Specifies the name of the resource."
}

output "id" {
  value       = azurerm_application_insights.example.id
  description = "Specifies the resource id of the resource."
}

output "instrumentation_key" {
  value       = azurerm_application_insights.example.instrumentation_key
  description = "Specifies the instrumentation key of the Application Insights."
}

output "app_id" {
  value       = azurerm_application_insights.example.app_id
  description = "Specifies the resource id of the resource."
}

output "connection_string" {
  value       = azurerm_application_insights.example.connection_string
  description = "Specifies the connection string of the Application Insights."
}