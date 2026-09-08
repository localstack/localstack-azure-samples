
output "id" {
  value       = azurerm_user_assigned_identity.example.id
  description = "Specifies the resource id of the workload user-defined managed identity"
}

output "location" {
  value       = azurerm_user_assigned_identity.example.location
  description = "Specifies the location of the workload user-defined managed identity"
}

output "name" {
  value       = azurerm_user_assigned_identity.example.name
  description = "Specifies the name of the workload user-defined managed identity"
}

output "client_id" {
  value       = azurerm_user_assigned_identity.example.client_id
  description = "Specifies the client id of the workload user-defined managed identity"
}

output "principal_id" {
  value       = azurerm_user_assigned_identity.example.principal_id
  description = "Specifies the principal id of the workload user-defined managed identity"
}