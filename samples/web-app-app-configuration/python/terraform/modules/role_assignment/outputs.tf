output "id" {
  description = "Specifies the resource id of the role assignment."
  value       = azurerm_role_assignment.assignment.id
}

output "name" {
  description = "Specifies the name (GUID) of the role assignment."
  value       = azurerm_role_assignment.assignment.name
}
