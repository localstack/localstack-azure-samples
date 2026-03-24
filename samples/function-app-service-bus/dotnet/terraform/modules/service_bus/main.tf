resource "azurerm_servicebus_namespace" "example" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = var.sku
  capacity                      = var.capacity
  premium_messaging_partitions  = var.premium_messaging_partitions
  local_auth_enabled            = var.local_auth_enabled
  public_network_access_enabled = var.public_network_access_enabled
  minimum_tls_version           = var.minimum_tls_version
  tags                          = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_servicebus_namespace_authorization_rule" "example" {
  name         = "${var.name}-auth-rule"
  namespace_id = azurerm_servicebus_namespace.example.id

  send   = true
  listen = true
  manage = true
}

resource "azurerm_servicebus_queue" "example" {
  for_each = var.queue_names

  name         = each.value
  namespace_id = azurerm_servicebus_namespace.example.id

  lock_duration                           = var.lock_duration
  max_message_size_in_kilobytes           = var.max_message_size_in_kilobytes
  max_size_in_megabytes                   = var.max_size_in_megabytes
  requires_duplicate_detection            = var.requires_duplicate_detection
  requires_session                        = var.requires_session
  default_message_ttl                     = var.default_message_ttl
  dead_lettering_on_message_expiration    = var.dead_lettering_on_message_expiration
  duplicate_detection_history_time_window = var.duplicate_detection_history_time_window
  max_delivery_count                      = var.max_delivery_count
  status                                  = var.status
  batched_operations_enabled              = var.batched_operations_enabled
  auto_delete_on_idle                     = var.auto_delete_on_idle
  partitioning_enabled                    = var.partitioning_enabled
  express_enabled                         = var.express_enabled
  forward_to                              = var.forward_to
  forward_dead_lettered_messages_to       = var.forward_dead_lettered_messages_to
}

resource "azurerm_monitor_diagnostic_setting" "example" {
  name                       = "DiagnosticsSettings"
  target_resource_id         = azurerm_servicebus_namespace.example.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "OperationalLogs"
  }

  enabled_log {
    category = "VNetAndIPFilteringLogs"
  }

  enabled_log {
    category = "RuntimeAuditLogs"
  }

  enabled_log {
    category = "ApplicationMetricsLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
