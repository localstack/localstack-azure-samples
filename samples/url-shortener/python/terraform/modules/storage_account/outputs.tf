output "id" {
  description = "Specifies the resource id of the storage account."
  value       = azurerm_storage_account.example.id
}

output "name" {
  description = "Specifies the name of the storage account."
  value       = azurerm_storage_account.example.name
}

output "primary_blob_endpoint" {
  description = "Specifies the primary blob endpoint of the storage account."
  value       = azurerm_storage_account.example.primary_blob_endpoint
}

output "container_names" {
  description = "Specifies the names of the blob containers of the storage account."
  value       = [for container in azurerm_storage_container.example : container.name]
}

output "primary_queue_endpoint" {
  description = "Specifies the primary queue endpoint of the storage account."
  value       = azurerm_storage_account.example.primary_queue_endpoint
}

output "primary_table_endpoint" {
  description = "Specifies the primary table endpoint of the storage account."
  value       = azurerm_storage_account.example.primary_table_endpoint
}

output "primary_access_key" {
  description = "Specifies the primary access key of the storage account."
  value       = azurerm_storage_account.example.primary_access_key
  sensitive   = true
}
