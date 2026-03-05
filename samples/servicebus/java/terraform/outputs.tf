output "resource_group_name" {
  description = "The name of the Resource Group."
  value       = azurerm_resource_group.example.name
}

output "namespace_name" {
  description = "The name of the Service Bus Namespace."
  value       = azurerm_servicebus_namespace.example.name
}

output "queue_name" {
  description = "The name of the Service Bus Queue."
  value       = azurerm_servicebus_queue.example.name
}


