# Local Variables
locals {
  resource_group_name       = "${var.prefix}-rg"
  storage_account_name      = "${var.prefix}storage${var.suffix}"
  app_service_plan_name     = "${var.prefix}-app-service-plan-${var.suffix}"
  function_app_name         = "${var.prefix}-functionapp-${var.suffix}"
  log_analytics_name        = "${var.prefix}-log-analytics-${var.suffix}"
  application_insights_name = "${var.prefix}-insights-${var.suffix}"
}

# Create the Log Analytics workspace that the Application Insights component sends its telemetry to
module "log_analytics" {
  source              = "./modules/log_analytics"
  name                = local.log_analytics_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  tags                = var.tags
}

# Create the workspace-based Application Insights component that collects the function app's invocations and logs
module "application_insights" {
  source              = "./modules/application_insights"
  name                = local.application_insights_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  workspace_id        = module.log_analytics.id
  tags                = var.tags
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  location = var.location
  name     = local.resource_group_name
  tags     = var.tags
}

# Create a storage account
resource "azurerm_storage_account" "example" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_replication_type = var.account_replication_type
  account_kind             = var.account_kind
  account_tier             = var.account_tier
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

# Create a service plan
resource "azurerm_service_plan" "example" {
  name                   = local.app_service_plan_name
  resource_group_name    = azurerm_resource_group.example.name
  location               = azurerm_resource_group.example.location
  sku_name               = var.sku_name
  os_type                = var.os_type
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Create a function app
resource "azurerm_linux_function_app" "example" {
  name                          = local.function_app_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  service_plan_id               = azurerm_service_plan.example.id
  storage_account_name          = azurerm_storage_account.example.name
  storage_account_access_key    = azurerm_storage_account.example.primary_access_key
  https_only                    = var.https_only
  public_network_access_enabled = var.public_network_access_enabled
  tags                          = var.tags
  functions_extension_version   = "~4"

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                              = var.always_on
    minimum_tls_version                    = var.minimum_tls_version
    application_insights_connection_string = module.application_insights.connection_string
    application_stack {
      dotnet_version              = var.dotnet_version
      use_dotnet_isolated_runtime = true
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME                  = var.runtime_name
    SCM_DO_BUILD_DURING_DEPLOYMENT            = "true"
    AzureWebJobsStorage                       = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};EndpointSuffix=core.windows.net;"
    WEBSITE_STORAGE_ACCOUNT_CONNECTION_STRING = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};EndpointSuffix=core.windows.net;"
    STORAGE_ACCOUNT_CONNECTION_STRING         = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};EndpointSuffix=core.windows.net;"
    INPUT_STORAGE_CONTAINER_NAME              = var.input_container_name
    OUTPUT_STORAGE_CONTAINER_NAME             = var.output_container_name
    INPUT_QUEUE_NAME                          = var.input_queue_name
    OUTPUT_QUEUE_NAME                         = var.output_queue_name
    TRIGGER_QUEUE_NAME                        = var.trigger_queue_name
    INPUT_TABLE_NAME                          = var.input_table_name
    OUTPUT_TABLE_NAME                         = var.output_table_name
    PLAYER_NAMES                              = var.player_names
    TIMER_SCHEDULE                            = var.timer_schedule
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Send the logs of the Functions host and of the functions (FunctionAppLogs) and the platform metrics of the function app to the Log Analytics workspace
resource "azurerm_monitor_diagnostic_setting" "function_app" {
  name                       = var.diagnostic_settings_name
  target_resource_id         = azurerm_linux_function_app.example.id
  log_analytics_workspace_id = module.log_analytics.id

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

# Send the platform metrics of the App Service plan to the Log Analytics workspace
resource "azurerm_monitor_diagnostic_setting" "app_service_plan" {
  name                       = var.diagnostic_settings_name
  target_resource_id         = azurerm_service_plan.example.id
  log_analytics_workspace_id = module.log_analytics.id

  dynamic "enabled_metric" {
    for_each = toset(var.metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}
