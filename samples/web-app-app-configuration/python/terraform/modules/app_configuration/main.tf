resource "azurerm_app_configuration" "store" {
  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  sku                        = var.sku
  local_auth_enabled         = var.local_auth_enabled
  public_network_access      = var.public_network_access
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = var.soft_delete_retention_days
  tags                       = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# One ARM child resource per key-value (see versions.tf for why AzAPI). The child resource name is the key,
# followed by a dollar sign and the label when the key-value carries one. A content type is written only
# when set, so a plain key-value keeps no content type, like one created with the Azure CLI.
resource "azapi_resource" "key_value" {
  for_each = var.key_values

  type      = "Microsoft.AppConfiguration/configurationStores/keyValues@${var.key_value_api_version}"
  parent_id = azurerm_app_configuration.store.id
  name      = each.value.label == null ? each.key : "${each.key}$${each.value.label}"
  body = {
    properties = merge(
      { value = each.value.value },
      each.value.content_type == null ? {} : { contentType = each.value.content_type },
    )
  }
}

resource "azurerm_monitor_diagnostic_setting" "settings" {
  name                       = var.diagnostic_setting_name
  target_resource_id         = azurerm_app_configuration.store.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

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
