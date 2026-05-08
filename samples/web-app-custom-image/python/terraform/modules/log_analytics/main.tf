resource "azurerm_log_analytics_workspace" "example" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  tags                = var.tags
  retention_in_days   = var.retention_in_days != null ? var.retention_in_days : null

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
