output "id" {
  value       = azurerm_service_plan.example.id
  description = "Specifies the resource id of the App Service Plan"
}

output "name" {
  value       = azurerm_service_plan.example.name
  description = "Specifies the name of the App Service Plan"
}

output "location" {
  value       = azurerm_service_plan.example.location
  description = "Specifies the location of the App Service Plan"
}

output "resource_group_name" {
  value       = azurerm_service_plan.example.resource_group_name
  description = "Specifies the resource group name of the App Service Plan"
}
