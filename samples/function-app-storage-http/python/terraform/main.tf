# Local Variables
locals {
  resource_group_name       = "${var.prefix}-rg"
  storage_account_name      = "${var.prefix}storage${var.suffix}"
  app_service_plan_name     = "${var.prefix}-app-service-plan-${var.suffix}"
  function_app_name         = "${var.prefix}-functionapp-${var.suffix}"
  log_analytics_name        = "${var.prefix}-log-analytics-${var.suffix}"
  application_insights_name = "${var.prefix}-insights-${var.suffix}"
  # The connection string the Functions host (AzureWebJobsStorage) and the bindings of the functions use
  storage_account_connection_string = "DefaultEndpointsProtocol=https;AccountName=${module.storage_account.name};AccountKey=${module.storage_account.primary_access_key};EndpointSuffix=core.windows.net;"
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  location = var.location
  name     = local.resource_group_name
  tags     = var.tags
}

# Create the Log Analytics workspace that receives the logs and metrics of the resources and the telemetry of the function app
module "log_analytics" {
  source              = "./modules/log_analytics"
  name                = local.log_analytics_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  tags                = var.tags
}

# Create the workspace-based Application Insights component that collects the function app's invocations, logs, exceptions, custom events and custom metrics
module "application_insights" {
  source              = "./modules/application_insights"
  name                = local.application_insights_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  workspace_id        = module.log_analytics.id
  tags                = var.tags
}

# Create the storage account and the diagnostic settings of the account and of its blob, queue and table services: the
# functions use all three, where the Functions host also keeps its own data, and create their containers, queues and
# tables themselves when they start
module "storage_account" {
  source                     = "./modules/storage_account"
  name                       = local.storage_account_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  account_kind               = var.account_kind
  account_tier               = var.account_tier
  account_replication_type   = var.account_replication_type
  diagnostic_services        = ["blob", "queue", "table"]
  log_analytics_workspace_id = module.log_analytics.id
  diagnostic_setting_name    = var.diagnostic_settings_name
  tags                       = var.tags
}

# Create the App Service plan and its diagnostic setting
module "app_service_plan" {
  source                     = "./modules/app_service_plan"
  name                       = local.app_service_plan_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  sku_name                   = var.sku_name
  os_type                    = var.os_type
  zone_balancing_enabled     = var.zone_balancing_enabled
  log_analytics_workspace_id = module.log_analytics.id
  diagnostic_setting_name    = var.diagnostic_settings_name
  metric_categories          = var.metric_categories
  tags                       = var.tags
}

# Create the function app and its diagnostic setting
module "function_app" {
  source                                 = "./modules/function_app"
  name                                   = local.function_app_name
  resource_group_name                    = azurerm_resource_group.example.name
  location                               = azurerm_resource_group.example.location
  service_plan_id                        = module.app_service_plan.id
  storage_account_name                   = module.storage_account.name
  storage_account_access_key             = module.storage_account.primary_access_key
  https_only                             = var.https_only
  public_network_access_enabled          = var.public_network_access_enabled
  always_on                              = var.always_on
  minimum_tls_version                    = var.minimum_tls_version
  application_insights_connection_string = module.application_insights.connection_string
  python_version                         = var.python_version
  identity_type                          = "SystemAssigned"
  log_analytics_workspace_id             = module.log_analytics.id
  diagnostic_setting_name                = var.diagnostic_settings_name
  log_categories                         = var.log_categories
  metric_categories                      = var.metric_categories
  tags                                   = var.tags

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = var.runtime_name
    # The remote build installs requirements.txt
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"
    # With telemetryMode set to OpenTelemetry in host.json, the Python worker sends the records of the function_app
    # logger, the exceptions it logs, the custom events and the custom metric to Application Insights
    PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY = "true"
    PYTHON_APPLICATIONINSIGHTS_LOGGER_NAME      = "function_app"
    AzureWebJobsStorage                         = local.storage_account_connection_string
    STORAGE_ACCOUNT_CONNECTION_STRING           = local.storage_account_connection_string
    INPUT_STORAGE_CONTAINER_NAME                = var.input_container_name
    OUTPUT_STORAGE_CONTAINER_NAME               = var.output_container_name
    INPUT_QUEUE_NAME                            = var.input_queue_name
    OUTPUT_QUEUE_NAME                           = var.output_queue_name
    TRIGGER_QUEUE_NAME                          = var.trigger_queue_name
    INPUT_TABLE_NAME                            = var.input_table_name
    OUTPUT_TABLE_NAME                           = var.output_table_name
    PLAYER_NAMES                                = var.player_names
    TIMER_SCHEDULE                              = var.timer_schedule
  }
}
