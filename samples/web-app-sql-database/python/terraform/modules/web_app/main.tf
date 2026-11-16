resource "azurerm_linux_web_app" "example" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = var.service_plan_id
  https_only                    = var.https_only
  virtual_network_subnet_id     = var.virtual_network_subnet_id
  public_network_access_enabled = var.public_network_access_enabled
  client_affinity_enabled       = var.client_affinity_enabled
  tags                          = var.tags

  identity {
    type         = var.identity_type
    identity_ids = var.identity_type == "UserAssigned" ? var.identity_ids : null
  }

  site_config {
    always_on              = var.always_on
    http2_enabled          = var.http2_enabled
    minimum_tls_version    = var.minimum_tls_version
    vnet_route_all_enabled = var.vnet_route_all_enabled
    application_stack {
      python_version = var.python_version
    }
  }

  app_settings = var.app_settings

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "example" {
  name                       = var.diagnostic_setting_name
  target_resource_id         = azurerm_linux_web_app.example.id
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
