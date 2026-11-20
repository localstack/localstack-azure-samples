resource "azurerm_storage_account" "example" {
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = var.account_kind
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  # The qrcodes container lets anyone read its blobs; new storage accounts disallow anonymous access unless the account
  # explicitly allows it
  allow_nested_items_to_be_public = var.allow_nested_items_to_be_public
  tags                            = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_storage_table" "example" {
  for_each = toset(var.table_names)

  name               = each.value
  storage_account_id = azurerm_storage_account.example.id
}

resource "azurerm_storage_queue" "example" {
  for_each = toset(var.queue_names)

  name               = each.value
  storage_account_id = azurerm_storage_account.example.id
}

resource "azurerm_storage_container" "example" {
  for_each = toset(var.container_names)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.example.id
  container_access_type = var.container_access_type
}

# The storage account exports only metrics; the logs of the requests to its blobs, queues and tables are exported by
# the diagnostic settings of its services.
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

resource "azurerm_monitor_diagnostic_setting" "services" {
  for_each = toset(var.diagnostic_services)

  name                       = var.diagnostic_setting_name
  target_resource_id         = "${azurerm_storage_account.example.id}/${each.value}Services/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.service_log_categories)
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
