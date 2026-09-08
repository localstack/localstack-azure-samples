output "resource_group_name" {
  value = local.resource_group_name
}

output "sql_server_name" {
  value = azurerm_mssql_server.example.name
}

output "sql_database_name" {
  value = azurerm_mssql_database.example.name
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

output "key_vault_name" {
  value = azurerm_key_vault.example.name
}

output "key_vault_url" {
  value = azurerm_key_vault.example.vault_uri
}

output "sql_connection_string_secret_uri" {
  value = azurerm_key_vault_secret.sql_connection_string.id
}