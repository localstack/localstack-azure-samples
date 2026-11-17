output "id" {
  description = "Specifies the resource id of the Key Vault."
  value       = azurerm_key_vault.vault.id
}

output "name" {
  description = "Specifies the name of the Key Vault."
  value       = azurerm_key_vault.vault.name
}

output "vault_uri" {
  description = "Specifies the URI of the Key Vault data plane."
  value       = azurerm_key_vault.vault.vault_uri
}

output "secret_ids" {
  description = "Specifies the versioned identifiers of the secrets, by secret name."
  value       = { for name, secret in azurerm_key_vault_secret.secret : name => secret.id }
}

output "secret_versionless_ids" {
  description = "Specifies the versionless identifiers of the secrets, by secret name. A reference built from one always follows the latest version of the secret."
  value       = { for name, secret in azurerm_key_vault_secret.secret : name => secret.versionless_id }
}
