resource "azurerm_linux_web_app" "example" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = var.service_plan_id
  https_only                    = var.https_only
  virtual_network_subnet_id     = var.virtual_network_subnet_id
  public_network_access_enabled = var.public_network_access_enabled
  client_affinity_enabled       = false
  tags                          = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = var.managed_identity_id != null ? [var.managed_identity_id] : []
  }

  site_config {
    always_on              = var.always_on
    http2_enabled          = var.http2_enabled
    minimum_tls_version    = var.minimum_tls_version
    vnet_route_all_enabled = var.vnet_route_all_enabled
    application_stack {
      docker_image_name        = "${var.image_name}:${var.image_tag}"
      docker_registry_url      = var.docker_registry_url
      docker_registry_username = var.docker_registry_username
      docker_registry_password = var.docker_registry_password
    }
  }

  app_settings = var.app_settings

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Deploy code from a public GitHub repo
resource "azurerm_app_service_source_control" "example" {
  count                  = var.repo_url == "" ? 0 : 1
  app_id                 = azurerm_linux_web_app.example.id
  repo_url               = var.repo_url
  branch                 = var.repo_branch
  use_manual_integration = true
  use_mercurial          = false
}

resource "azurerm_monitor_diagnostic_setting" "example" {
  name                       = "DiagnosticsSettings"
  target_resource_id         = azurerm_linux_web_app.example.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServiceAppLogs"
  }

  enabled_log {
    category = "AppServiceAuditLogs"
  }

  enabled_log {
    category = "AppServiceIPSecAuditLogs"
  }

  enabled_log {
    category = "AppServicePlatformLogs"
  }

  enabled_log {
    category = "AppServiceAuthenticationLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}