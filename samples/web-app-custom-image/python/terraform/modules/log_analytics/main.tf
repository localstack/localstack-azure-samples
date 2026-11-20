resource "azurerm_log_analytics_workspace" "example" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  tags                = var.tags
  retention_in_days   = var.retention_in_days != "" ? var.retention_in_days : null

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Query auditing: the diagnostic setting of a workspace can send its audit records to the workspace itself.
resource "azurerm_monitor_diagnostic_setting" "example" {
  name                       = var.diagnostic_setting_name
  target_resource_id         = azurerm_log_analytics_workspace.example.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id

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
