output "resource_group_name" {
  description = "Resource group holding the pipeline."
  value       = azurerm_resource_group.main.name
}

output "eventhub_namespace_name" {
  description = "Event Hubs namespace name."
  value       = module.event_hubs.name
}

output "event_hub_name" {
  description = "Event hub carrying payment events."
  value       = module.event_hubs.event_hub_name
}

output "alert_hub_name" {
  description = "Event hub carrying fraud alerts."
  value       = module.event_hubs.alert_hub_name
}

output "consumer_groups" {
  description = "Consumer groups on the payments hub."
  value       = module.event_hubs.consumer_groups
}

output "fraud_consumer_group" {
  description = "Consumer group the fraud detector reads from."
  value       = local.fraud_consumer_group
}

output "schema_group_name" {
  description = "Schema Registry group holding the payment contract."
  value       = module.event_hubs.schema_group_name
}

output "storage_account_name" {
  description = "Storage account used for Capture archives and checkpoints."
  value       = module.storage_account.name
}

output "capture_container_name" {
  description = "Blob container receiving Capture archives."
  value       = one(module.storage_account.container_names)
}

output "key_vault_name" {
  description = "Key vault holding the connection strings."
  value       = module.key_vault.name
}

output "log_analytics_workspace_name" {
  description = "Log Analytics workspace the diagnostic settings and Application Insights send to."
  value       = module.log_analytics.name
}

output "application_insights_name" {
  description = "Application Insights resource the two apps send their telemetry to."
  value       = module.application_insights.name
}

output "function_app_name" {
  description = "Function App running fraud detection."
  value       = module.function_app.name
}

output "web_app_name" {
  description = "Web App running the operations dashboard."
  value       = module.web_app.name
}

output "dashboard_url" {
  description = "URL of the operations dashboard."
  value       = "https://${module.web_app.default_hostname}"
}

output "eventhub_send_connection_string" {
  description = "Send-only connection string for the payments hub."
  value       = module.event_hubs.send_connection_string
  sensitive   = true
}

output "eventhub_listen_connection_string" {
  description = "Listen-only connection string for the payments hub."
  value       = module.event_hubs.listen_connection_string
  sensitive   = true
}

output "eventhub_alert_send_connection_string" {
  description = "Send-only connection string for the fraud-alerts hub."
  value       = module.event_hubs.alert_send_connection_string
  sensitive   = true
}

output "eventhub_namespace_connection_string" {
  description = "Namespace-level connection string used by the demo scripts (Kafka publishing and reading both hubs)."
  value       = module.event_hubs.namespace_connection_string
  sensitive   = true
}

output "storage_connection_string" {
  description = "Storage account connection string."
  value       = local.storage_connection_string
  sensitive   = true
}
