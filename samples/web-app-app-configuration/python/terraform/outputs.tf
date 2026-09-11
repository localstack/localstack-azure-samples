output "resource_group_name" {
  description = "Specifies the name of the resource group."
  value       = local.resource_group_name
}

output "postgres_server_name" {
  description = "Specifies the name of the PostgreSQL flexible server."
  value       = module.postgres_flexible_server.name
}

output "postgres_fqdn" {
  description = "Specifies the fully qualified domain name of the PostgreSQL flexible server (on the emulator it carries the port)."
  value       = module.postgres_flexible_server.fqdn
}

output "postgres_database_name" {
  description = "Specifies the name of the application database."
  value       = module.postgres_flexible_server.database_name
}

output "app_service_plan_name" {
  description = "Specifies the name of the App Service plan."
  value       = module.app_service_plan.name
}

output "web_app_name" {
  description = "Specifies the name of the Web App."
  value       = module.web_app.name
}

output "web_app_url" {
  description = "Specifies the default hostname of the Web App."
  value       = module.web_app.default_hostname
}

output "app_configuration_name" {
  description = "Specifies the name of the App Configuration store."
  value       = module.app_configuration.name
}

output "app_configuration_endpoint" {
  description = "Specifies the endpoint of the App Configuration store the Web App loads its settings from."
  value       = module.app_configuration.endpoint
}

output "key_vault_name" {
  description = "Specifies the name of the Key Vault."
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "Specifies the URI of the Key Vault."
  value       = module.key_vault.vault_uri
}

output "managed_identity_name" {
  description = "Specifies the name of the user-assigned managed identity of the Web App."
  value       = module.managed_identity.name
}

output "managed_identity_client_id" {
  description = "Specifies the client id of the user-assigned managed identity, handed to the Web App as AZURE_CLIENT_ID."
  value       = module.managed_identity.client_id
}

output "managed_identity_principal_id" {
  description = "Specifies the principal id of the user-assigned managed identity, the id its role assignments are keyed on."
  value       = module.managed_identity.principal_id
}
