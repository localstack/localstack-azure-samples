output "id" {
  value = azurerm_eventhub_namespace.example.id
}

output "name" {
  value = azurerm_eventhub_namespace.example.name
}

output "telemetry_hub_name" {
  value = azurerm_eventhub.telemetry.name
}

output "notification_hub_name" {
  value = azurerm_eventhub.notifications.name
}

output "notification_hub_id" {
  value = azurerm_eventhub.notifications.id
}

output "curated_hub_name" {
  value = azurerm_eventhub.curated.name
}

output "capture_consumer_group" {
  value = azurerm_eventhub_consumer_group.capture_processor.name
}

output "send_connection_string" {
  value     = azurerm_eventhub_authorization_rule.telemetry_send.primary_connection_string
  sensitive = true
}

output "listen_connection_string" {
  value     = azurerm_eventhub_namespace_authorization_rule.pipeline_listen.primary_connection_string
  sensitive = true
}

output "namespace_connection_string" {
  value     = azurerm_eventhub_namespace.example.default_primary_connection_string
  sensitive = true
}
