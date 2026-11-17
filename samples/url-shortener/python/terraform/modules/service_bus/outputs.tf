output "namespace_connection_string" {
  value = azurerm_servicebus_namespace.example.default_primary_connection_string
}

output "shared_access_policy_primarykey" {
  value = azurerm_servicebus_namespace.example.default_primary_key
}

output "name" {
  value       = azurerm_servicebus_namespace.example.name
  description = "Specifies the name of the Service Bus namespace."
}

output "id" {
  value       = azurerm_servicebus_namespace.example.id
  description = "Specifies the resource id of the Service Bus namespace."
}
