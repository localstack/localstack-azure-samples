resource "azurerm_eventhub_namespace" "example" {
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = var.sku
  capacity                 = var.capacity
  auto_inflate_enabled     = true
  maximum_throughput_units = var.maximum_throughput_units
  minimum_tls_version      = "1.2"
  tags                     = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# The payments hub archives itself to Blob Storage as Avro: the cold path needs no consumer code at all.
resource "azurerm_eventhub" "payments" {
  name              = var.event_hub_name
  namespace_id      = azurerm_eventhub_namespace.example.id
  partition_count   = var.partition_count
  message_retention = var.message_retention_days

  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = var.capture_interval_in_seconds
    size_limit_in_bytes = var.capture_size_limit_in_bytes
    skip_empty_archives = true

    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = var.capture_container_name
      storage_account_id  = var.capture_storage_account_id
    }
  }
}

resource "azurerm_eventhub" "alerts" {
  name              = var.alert_hub_name
  namespace_id      = azurerm_eventhub_namespace.example.id
  partition_count   = var.alert_partition_count
  message_retention = var.message_retention_days
}

# Each downstream system reads the same log at its own pace, with its own offsets.
resource "azurerm_eventhub_consumer_group" "groups" {
  for_each = toset(var.consumer_groups)

  name                = each.value
  namespace_name      = azurerm_eventhub_namespace.example.name
  eventhub_name       = azurerm_eventhub.payments.name
  resource_group_name = var.resource_group_name
}

# Least privilege: producers may only Send, consumers may only Listen.
resource "azurerm_eventhub_authorization_rule" "send" {
  name                = "payments-send"
  namespace_name      = azurerm_eventhub_namespace.example.name
  eventhub_name       = azurerm_eventhub.payments.name
  resource_group_name = var.resource_group_name

  listen = false
  send   = true
  manage = false
}

resource "azurerm_eventhub_authorization_rule" "listen" {
  name                = "payments-listen"
  namespace_name      = azurerm_eventhub_namespace.example.name
  eventhub_name       = azurerm_eventhub.payments.name
  resource_group_name = var.resource_group_name

  listen = true
  send   = false
  manage = false
}

resource "azurerm_eventhub_authorization_rule" "alerts_send" {
  name                = "alerts-send"
  namespace_name      = azurerm_eventhub_namespace.example.name
  eventhub_name       = azurerm_eventhub.alerts.name
  resource_group_name = var.resource_group_name

  listen = false
  send   = true
  manage = false
}

# The dashboard reads both hubs plus partition runtime metadata, which no single entity-level rule covers. That calls
# for a namespace-wide Listen rule, not the namespace Manage key: a reader should never hold Send or Manage.
resource "azurerm_eventhub_namespace_authorization_rule" "dashboard_listen" {
  name                = "dashboard-listen"
  namespace_name      = azurerm_eventhub_namespace.example.name
  resource_group_name = var.resource_group_name

  listen = true
  send   = false
  manage = false
}

# The versioned contract producers and consumers agree on.
resource "azurerm_eventhub_namespace_schema_group" "payments" {
  name                 = var.schema_group_name
  namespace_id         = azurerm_eventhub_namespace.example.id
  schema_compatibility = "Forward"
  schema_type          = "Avro"
}

# The resource logs and the platform metrics of the namespace
resource "azurerm_monitor_diagnostic_setting" "example" {
  name                           = var.diagnostic_setting_name
  target_resource_id             = azurerm_eventhub_namespace.example.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = var.log_analytics_destination_type

  dynamic "enabled_log" {
    for_each = toset(var.log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}
