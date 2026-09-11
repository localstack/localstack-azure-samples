output "id" {
  description = "Specifies the resource id of the App Configuration store."
  value       = azurerm_app_configuration.store.id
}

output "name" {
  description = "Specifies the name of the App Configuration store."
  value       = azurerm_app_configuration.store.name
}

output "endpoint" {
  description = "Specifies the endpoint of the App Configuration store, read back from the service: https://<store>.azconfig.io on Azure, https://<store>.azure.localhost.localstack.cloud:4566 on the emulator."
  value       = azurerm_app_configuration.store.endpoint
}

output "key_value_ids" {
  description = "Specifies the resource ids of the key-values, by key."
  value       = { for key, key_value in azapi_resource.key_value : key => key_value.id }
}
