# Make the Key Vault key the TDE protector of the SQL server
resource "azurerm_mssql_server_transparent_data_encryption" "example" {
  server_id             = var.server_id
  key_vault_key_id      = var.key_vault_key_id
  auto_rotation_enabled = var.auto_rotation_enabled
}
