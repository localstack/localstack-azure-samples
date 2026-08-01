output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.main.name
}

output "web_app_name" {
  value = azurerm_linux_web_app.web.name
}

output "function_app_name" {
  value = azurerm_linux_function_app.worker.name
}

output "web_app_host" {
  value = azurerm_linux_web_app.web.default_hostname
}

output "postgres_host" {
  value = local.pg_host
}

output "postgres_port" {
  value = local.pg_port
}

output "postgres_password" {
  value     = random_password.postgres.result
  sensitive = true
}
