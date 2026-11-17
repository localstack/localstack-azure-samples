resource "azurerm_eventhub_namespace" "example" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  capacity            = 1
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# The hub Capture archives. skip_empty_archives keeps Event Hubs from raising a
# CaptureFileCreated for a window that saw no readings.
resource "azurerm_eventhub" "telemetry" {
  name              = var.telemetry_hub_name
  namespace_id      = azurerm_eventhub_namespace.example.id
  partition_count   = var.telemetry_partition_count
  message_retention = var.retention_days

  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = var.capture_interval_seconds
    size_limit_in_bytes = var.capture_size_limit_bytes
    skip_empty_archives = true

    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = var.capture_container_name
      storage_account_id  = var.capture_storage_account_id
    }
  }
}

resource "azurerm_eventhub" "notifications" {
  name              = var.notification_hub_name
  namespace_id      = azurerm_eventhub_namespace.example.id
  partition_count   = 2
  message_retention = var.retention_days
}

resource "azurerm_eventhub" "curated" {
  name              = var.curated_hub_name
  namespace_id      = azurerm_eventhub_namespace.example.id
  partition_count   = 2
  message_retention = var.retention_days
}

# The processor keeps its own position in the notifications stream.
resource "azurerm_eventhub_consumer_group" "capture_processor" {
  name                = var.capture_consumer_group
  namespace_name      = azurerm_eventhub_namespace.example.name
  eventhub_name       = azurerm_eventhub.notifications.name
  resource_group_name = var.resource_group_name
}

# Least privilege: producers may only Send to the telemetry hub.
resource "azurerm_eventhub_authorization_rule" "telemetry_send" {
  name                = "telemetry-send"
  namespace_name      = azurerm_eventhub_namespace.example.name
  eventhub_name       = azurerm_eventhub.telemetry.name
  resource_group_name = var.resource_group_name

  listen = false
  send   = true
  manage = false
}

# The demo scripts read all three hubs, so this rule is namespace-wide - but Listen only.
resource "azurerm_eventhub_namespace_authorization_rule" "pipeline_listen" {
  name                = "pipeline-listen"
  namespace_name      = azurerm_eventhub_namespace.example.name
  resource_group_name = var.resource_group_name

  listen = true
  send   = false
  manage = false
}

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
