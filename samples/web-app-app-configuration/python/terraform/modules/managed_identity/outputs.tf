output "id" {
  description = "Specifies the resource id of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.identity.id
}

output "name" {
  description = "Specifies the name of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.identity.name
}

output "client_id" {
  description = "Specifies the client id of the user-assigned managed identity, the value a workload passes as AZURE_CLIENT_ID."
  value       = azurerm_user_assigned_identity.identity.client_id
}

output "principal_id" {
  description = "Specifies the principal (object) id of the user-assigned managed identity, the value role assignments are keyed on."
  value       = azurerm_user_assigned_identity.identity.principal_id
}

output "tenant_id" {
  description = "Specifies the tenant id of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.identity.tenant_id
}
