output "resource_group_name" {
  description = "Resource group holding the pipeline."
  value       = azurerm_resource_group.main.name
}

output "eventhub_namespace_name" {
  description = "Event Hubs namespace name."
  value       = azurerm_eventhub_namespace.main.name
}

output "event_hub_name" {
  description = "Event hub carrying payment events."
  value       = azurerm_eventhub.payments.name
}

output "alert_hub_name" {
  description = "Event hub carrying fraud alerts."
  value       = azurerm_eventhub.alerts.name
}

output "consumer_groups" {
  description = "Consumer groups on the payments hub."
  value       = [for group in azurerm_eventhub_consumer_group.groups : group.name]
}

output "fraud_consumer_group" {
  description = "Consumer group the fraud detector reads from."
  value       = local.fraud_consumer_group
}

output "schema_group_name" {
  description = "Schema Registry group holding the payment contract."
  value       = azurerm_eventhub_namespace_schema_group.payments.name
}

output "storage_account_name" {
  description = "Storage account used for Capture archives and checkpoints."
  value       = azurerm_storage_account.main.name
}

output "capture_container_name" {
  description = "Blob container receiving Capture archives."
  value       = azurerm_storage_container.capture.name
}

output "key_vault_name" {
  description = "Key vault holding the connection strings."
  value       = azurerm_key_vault.main.name
}

output "function_app_name" {
  description = "Function App running fraud detection."
  value       = azurerm_linux_function_app.fraud.name
}

output "web_app_name" {
  description = "Web App running the operations dashboard."
  value       = azurerm_linux_web_app.dashboard.name
}

output "dashboard_url" {
  description = "URL of the operations dashboard."
  value       = "https://${azurerm_linux_web_app.dashboard.default_hostname}"
}

output "eventhub_send_connection_string" {
  description = "Send-only connection string for the payments hub."
  value       = azurerm_eventhub_authorization_rule.send.primary_connection_string
  sensitive   = true
}

output "eventhub_listen_connection_string" {
  description = "Listen-only connection string for the payments hub."
  value       = azurerm_eventhub_authorization_rule.listen.primary_connection_string
  sensitive   = true
}

output "eventhub_alert_send_connection_string" {
  description = "Send-only connection string for the fraud-alerts hub."
  value       = azurerm_eventhub_authorization_rule.alerts_send.primary_connection_string
  sensitive   = true
}

output "eventhub_namespace_connection_string" {
  description = "Namespace-level connection string used by the demo scripts (Kafka publishing and reading both hubs)."
  value       = azurerm_eventhub_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "storage_connection_string" {
  description = "Storage account connection string."
  value       = local.storage_connection_string
  sensitive   = true
}
