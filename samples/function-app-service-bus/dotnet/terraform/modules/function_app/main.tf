resource "azurerm_linux_function_app" "example" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = var.service_plan_id
  storage_account_name          = var.storage_account_name
  storage_account_access_key    = var.storage_account_access_key
  https_only                    = var.https_only
  virtual_network_subnet_id     = var.virtual_network_subnet_id
  public_network_access_enabled = var.public_network_access_enabled
  tags                          = var.tags

  identity {
    type         = var.managed_identity_type
    identity_ids = var.managed_identity_type == "UserAssigned" ? [var.managed_identity_id] : null
  }

  site_config {
    always_on              = var.always_on
    http2_enabled          = var.http2_enabled
    minimum_tls_version    = var.minimum_tls_version
    vnet_route_all_enabled = var.vnet_route_all_enabled
    application_stack {
      dotnet_version              = var.dotnet_version
      java_version                = var.java_version
      node_version                = var.node_version
      python_version              = var.python_version
      use_dotnet_isolated_runtime = var.use_dotnet_isolated_runtime
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
  app_id                 = azurerm_linux_function_app.example.id
  repo_url               = var.repo_url
  branch                 = var.repo_branch
  use_manual_integration = true
  use_mercurial          = false
}

resource "azurerm_monitor_diagnostic_setting" "example" {
  name                       = "DiagnosticsSettings"
  target_resource_id         = azurerm_linux_function_app.example.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "FunctionAppLogs"
  }

  enabled_log {
    category = "AppServiceAuthenticationLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}