output "resource_group_name" {
  value = local.resource_group_name
}

output "sql_server_name" {
  value = module.sql_server.name
}

output "sql_database_name" {
  value = module.sql_server.database_name
}

output "app_service_plan_name" {
  value = module.app_service_plan.name
}

output "web_app_name" {
  value = module.web_app.name
}

output "web_app_url" {
  value = module.web_app.default_hostname
}

output "key_vault_name" {
  value = module.key_vault.name
}

output "key_vault_url" {
  value = module.key_vault.vault_uri
}

output "sql_connection_string_secret_uri" {
  value = module.key_vault.secret_id
}

output "log_analytics_name" {
  value = module.log_analytics_workspace.name
}

output "application_insights_name" {
  value = module.application_insights.name
}
