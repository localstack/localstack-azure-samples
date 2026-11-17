output "id" {
  value = azurerm_eventhub_namespace.example.id
}

output "name" {
  value = azurerm_eventhub_namespace.example.name
}

output "event_hub_name" {
  value = azurerm_eventhub.payments.name
}

output "alert_hub_name" {
  value = azurerm_eventhub.alerts.name
}

output "consumer_groups" {
  value = [for group in azurerm_eventhub_consumer_group.groups : group.name]
}

output "schema_group_name" {
  value = azurerm_eventhub_namespace_schema_group.payments.name
}

output "send_connection_string" {
  value     = azurerm_eventhub_authorization_rule.send.primary_connection_string
  sensitive = true
}

output "listen_connection_string" {
  value     = azurerm_eventhub_authorization_rule.listen.primary_connection_string
  sensitive = true
}

output "alert_send_connection_string" {
  value     = azurerm_eventhub_authorization_rule.alerts_send.primary_connection_string
  sensitive = true
}

output "dashboard_listen_connection_string" {
  value     = azurerm_eventhub_namespace_authorization_rule.dashboard_listen.primary_connection_string
  sensitive = true
}

output "namespace_connection_string" {
  value     = azurerm_eventhub_namespace.example.default_primary_connection_string
  sensitive = true
}
