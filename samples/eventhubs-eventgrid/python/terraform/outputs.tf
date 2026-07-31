output "resource_group_name" {
  description = "Resource group holding the pipeline."
  value       = azurerm_resource_group.main.name
}

output "eventhub_namespace_name" {
  description = "Event Hubs namespace."
  value       = azurerm_eventhub_namespace.main.name
}

output "telemetry_hub_name" {
  description = "Hub that devices publish to."
  value       = azurerm_eventhub.telemetry.name
}

output "notification_hub_name" {
  description = "Hub that Event Grid delivers CaptureFileCreated to."
  value       = azurerm_eventhub.notifications.name
}

output "curated_hub_name" {
  description = "Hub that receives the per-device summaries."
  value       = azurerm_eventhub.curated.name
}

output "capture_consumer_group" {
  description = "Consumer group the processor uses."
  value       = azurerm_eventhub_consumer_group.capture_processor.name
}

output "capture_container_name" {
  description = "Blob container receiving Capture archives."
  value       = azurerm_storage_container.capture.name
}

output "storage_account_name" {
  description = "Storage account holding archives and function state."
  value       = azurerm_storage_account.main.name
}

output "system_topic_name" {
  description = "Event Grid system topic over the namespace."
  value       = azurerm_eventgrid_system_topic.namespace.name
}

output "event_subscription_name" {
  description = "Event Grid subscription delivering into the notifications hub."
  value       = azurerm_eventgrid_system_topic_event_subscription.capture_to_eventhub.name
}

output "function_app_name" {
  description = "Function App running the capture processor."
  value       = azurerm_linux_function_app.processor.name
}

output "temperature_limit" {
  description = "Excursion threshold used by the processor."
  value       = var.temperature_limit
}

output "eventhub_send_connection_string" {
  description = "Send-only connection string for the telemetry hub."
  value       = azurerm_eventhub_authorization_rule.telemetry_send.primary_connection_string
  sensitive   = true
}

output "eventhub_listen_connection_string" {
  description = "Namespace-wide listen-only connection string used by the demo scripts."
  value       = azurerm_eventhub_namespace_authorization_rule.pipeline_listen.primary_connection_string
  sensitive   = true
}

output "eventhub_namespace_connection_string" {
  description = "Namespace-level connection string (used for the function app settings)."
  value       = azurerm_eventhub_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "storage_connection_string" {
  description = "Storage connection string in the explicit-endpoint form the Functions host can parse."
  value       = local.storage_connection_string
  sensitive   = true
}
