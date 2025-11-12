output "resource_group_name" {
  value = local.resource_group_name
}

output "cosmosdb_account_name" {
  value = azurerm_cosmosdb_account.example.name
}

output "cosmosdb_document_endpoint" {
  value = azurerm_cosmosdb_account.example.endpoint
}

output "app_service_plan_name" {
  value = azurerm_service_plan.example.name
}

output "web_app_name" {
  value = azurerm_linux_web_app.example.name
}

output "web_app_url" {
  value = azurerm_linux_web_app.example.default_hostname
}