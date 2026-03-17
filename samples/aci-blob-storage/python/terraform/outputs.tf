output "resource_group_name" {
  value = azurerm_resource_group.example.name
}

output "storage_account_name" {
  value = azurerm_storage_account.example.name
}

output "key_vault_name" {
  value = azurerm_key_vault.example.name
}

output "acr_name" {
  value = azurerm_container_registry.example.name
}

output "acr_login_server" {
  value = azurerm_container_registry.example.login_server
}

output "aci_group_name" {
  value = azurerm_container_group.example.name
}

output "fqdn" {
  value = azurerm_container_group.example.fqdn
}
