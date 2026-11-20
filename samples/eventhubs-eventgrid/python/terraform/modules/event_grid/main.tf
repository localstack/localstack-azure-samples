# A system topic is how a subscriber reaches the events a resource raises about itself; Event Hubs
# raises exactly one, Microsoft.EventHub.CaptureFileCreated.
resource "azurerm_eventgrid_system_topic" "example" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  source_resource_id  = var.source_resource_id
  topic_type          = "Microsoft.Eventhub.Namespaces"
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Delivering to an event hub turns the notification into a stream event, so an ordinary Event Hubs
# trigger can consume it: no public webhook, and a durable backlog if the processor is down.
resource "azurerm_eventgrid_system_topic_event_subscription" "example" {
  name                  = var.subscription_name
  system_topic          = azurerm_eventgrid_system_topic.example.name
  resource_group_name   = var.resource_group_name
  eventhub_id           = var.eventhub_id
  event_delivery_schema = "EventGridSchema"
}

# The deliveries the subscription failed to make (AegDeliveryFailureLogs) and the metrics of the topic
resource "azurerm_monitor_diagnostic_setting" "example" {
  name                       = var.diagnostic_setting_name
  target_resource_id         = azurerm_eventgrid_system_topic.example.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "DeliveryFailures"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
