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
