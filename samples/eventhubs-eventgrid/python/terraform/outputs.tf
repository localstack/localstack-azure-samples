output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "eventhub_namespace_name" {
  value = module.event_hubs.name
}

output "telemetry_hub_name" {
  value = module.event_hubs.telemetry_hub_name
}

output "notification_hub_name" {
  value = module.event_hubs.notification_hub_name
}

output "curated_hub_name" {
  value = module.event_hubs.curated_hub_name
}

output "capture_consumer_group" {
  value = module.event_hubs.capture_consumer_group
}

output "capture_container_name" {
  value = one(module.storage_account.container_names)
}

output "storage_account_name" {
  value = module.storage_account.name
}

output "system_topic_name" {
  value = module.event_grid.name
}

output "event_subscription_name" {
  value = module.event_grid.subscription_name
}

output "function_app_name" {
  value = module.function_app.name
}

output "temperature_limit" {
  value = var.temperature_limit
}

output "log_analytics_name" {
  value = module.log_analytics.name
}

output "application_insights_name" {
  value = module.application_insights.name
}

output "eventhub_send_connection_string" {
  value     = module.event_hubs.send_connection_string
  sensitive = true
}

output "eventhub_listen_connection_string" {
  value     = module.event_hubs.listen_connection_string
  sensitive = true
}

output "eventhub_namespace_connection_string" {
  value     = module.event_hubs.namespace_connection_string
  sensitive = true
}

output "storage_connection_string" {
  value     = local.storage_connection_string
  sensitive = true
}
