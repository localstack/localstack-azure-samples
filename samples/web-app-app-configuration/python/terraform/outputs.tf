output "resource_group_name" {
  value = local.resource_group_name
}

output "postgres_server_name" {
  value = module.postgres_flexible_server.name
}

output "postgres_fqdn" {
  value = module.postgres_flexible_server.fqdn
}

output "postgres_database_name" {
  value = module.postgres_flexible_server.database_name
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

output "app_configuration_name" {
  value = azurerm_app_configuration.store.name
}

output "app_configuration_endpoint" {
  value = azurerm_app_configuration.store.endpoint
}

output "key_vault_name" {
  value = azurerm_key_vault.vault.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.vault.vault_uri
}

output "managed_identity_name" {
  value = azurerm_user_assigned_identity.web_app.name
}

output "managed_identity_client_id" {
  value = azurerm_user_assigned_identity.web_app.client_id
}

output "managed_identity_principal_id" {
  value = azurerm_user_assigned_identity.web_app.principal_id
}
