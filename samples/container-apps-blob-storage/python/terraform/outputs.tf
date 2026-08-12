output "resource_group_name" {
  value = azurerm_resource_group.example.name
}

output "storage_account_name" {
  value = azurerm_storage_account.example.name
}

output "acr_name" {
  value = data.azurerm_container_registry.example.name
}

output "acr_login_server" {
  value = data.azurerm_container_registry.example.login_server
}

output "environment_name" {
  value = azurerm_container_app_environment.example.name
}

output "app_name" {
  value = azurerm_container_app.example.name
}

output "fqdn" {
  value = azurerm_container_app.example.ingress[0].fqdn
}

output "latest_revision_name" {
  value = azurerm_container_app.example.latest_revision_name
}
