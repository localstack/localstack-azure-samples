locals {
  # The app this module created, on whichever plan
  function_app_id = one(concat(azurerm_linux_function_app.example[*].id, azurerm_function_app_flex_consumption.example[*].id))
}

# The app on any plan but Flex Consumption; a deployment made before the module created a Flex Consumption app keeps it
moved {
  from = azurerm_linux_function_app.example
  to   = azurerm_linux_function_app.example[0]
}

resource "azurerm_linux_function_app" "example" {
  count                         = var.is_flex_consumption ? 0 : 1
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

# The app on the Flex Consumption plan, which takes its runtime, scale and deployment storage from its function app
# configuration, in place of the site configuration's always_on, application_stack and vnet_route_all_enabled (Flex
# Consumption plan deprecations, App settings reference for Azure Functions)
resource "azurerm_function_app_flex_consumption" "example" {
  count                         = var.is_flex_consumption ? 1 : 0
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = var.service_plan_id
  storage_container_type        = "blobContainer"
  storage_container_endpoint    = var.storage_container_endpoint
  storage_authentication_type   = "StorageAccountConnectionString"
  storage_access_key            = var.storage_account_access_key
  runtime_name                  = var.runtime_name
  runtime_version               = var.runtime_version
  maximum_instance_count        = var.maximum_instance_count
  instance_memory_in_mb         = var.instance_memory_in_mb
  https_only                    = var.https_only
  virtual_network_subnet_id     = var.virtual_network_subnet_id
  public_network_access_enabled = var.public_network_access_enabled
  tags                          = var.tags

  identity {
    type         = var.managed_identity_type
    identity_ids = var.managed_identity_type == "UserAssigned" ? [var.managed_identity_id] : null
  }

  site_config {
    http2_enabled       = var.http2_enabled
    minimum_tls_version = var.minimum_tls_version
  }

  app_settings = var.app_settings

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "example" {
  name                       = "DiagnosticsSettings"
  target_resource_id         = local.function_app_id
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