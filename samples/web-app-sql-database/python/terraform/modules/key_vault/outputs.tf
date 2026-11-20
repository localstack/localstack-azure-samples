output "id" {
  value       = azurerm_key_vault.example.id
  description = "Specifies the resource id of the Key Vault"
}

output "name" {
  value       = azurerm_key_vault.example.name
  description = "Specifies the name of the Key Vault"
}

output "vault_uri" {
  value       = azurerm_key_vault.example.vault_uri
  description = "Specifies the URI of the Key Vault"
}

output "tde_key_id" {
  value       = azurerm_key_vault_key.tde.id
  description = "Specifies the versioned id of the TDE protector key, available once the SQL server's identity may use it"
  # The TDE protector can only be set once the server's identity has its access policy
  depends_on = [azurerm_key_vault_access_policy.sql_server]
}

output "secret_name" {
  value       = azurerm_key_vault_secret.sql_connection_string.name
  description = "Specifies the name of the secret that holds the SQL connection string"
}

output "secret_id" {
  value       = azurerm_key_vault_secret.sql_connection_string.id
  description = "Specifies the id of the secret that holds the SQL connection string"
}

output "certificate_name" {
  value       = azurerm_key_vault_certificate.example.name
  description = "Specifies the name of the certificate the web app serves HTTPS with"
}
