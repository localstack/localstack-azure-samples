output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "storage_account_name" {
  value = module.storage_account.name
}

output "key_vault_name" {
  value = module.key_vault.name
}

output "log_analytics_workspace_name" {
  value = module.log_analytics_workspace.name
}

output "application_insights_name" {
  value = module.application_insights.name
}

output "web_app_name" {
  value = module.web_app.name
}

output "function_app_name" {
  value = module.function_app.name
}

output "web_app_host" {
  value = module.web_app.default_hostname
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
