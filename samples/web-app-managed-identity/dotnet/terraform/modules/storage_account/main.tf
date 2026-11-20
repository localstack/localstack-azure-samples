resource "azurerm_storage_account" "example" {
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = var.account_kind
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  tags                     = var.tags

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_storage_container" "example" {
  for_each = toset(var.container_names)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.example.id
  container_access_type = "private"
}

# The storage account exports only metrics; the logs of the requests to its blobs are exported by its blob service.
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  name                       = var.diagnostic_setting_name
  target_resource_id         = azurerm_storage_account.example.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_metric" {
    for_each = toset(var.metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "blob_service" {
  name                       = var.diagnostic_setting_name
  target_resource_id         = "${azurerm_storage_account.example.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.blob_log_categories)
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
