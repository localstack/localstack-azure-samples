# Local Variables
locals {
  resource_group_name       = "${var.prefix}-rg"
  storage_account_name      = "${var.prefix}storage${var.suffix}"
  app_service_plan_name     = "${var.prefix}-app-service-plan-${var.suffix}"
  function_app_name         = "${var.prefix}-functionapp-${var.suffix}"
  managed_identity_name     = "${var.prefix}-identity-${var.suffix}"
  log_analytics_name        = "${var.prefix}-log-analytics-${var.suffix}"
  application_insights_name = "${var.prefix}-insights-${var.suffix}"
  # The principal id the storage roles are assigned to: the user-assigned identity's, or the function app's own
  principal_id = var.managed_identity_type == "UserAssigned" ? module.managed_identity[0].principal_id : module.function_app.principal_id
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  name     = local.resource_group_name
  location = var.location
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

# Create the storage account, its input and output containers, and the diagnostic settings of the account and of the
# blob, queue and table services, which the Functions host uses for its own data (AzureWebJobsStorage)
module "storage_account" {
  source                     = "./modules/storage_account"
  name                       = local.storage_account_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  account_kind               = var.account_kind
  account_tier               = var.account_tier
  account_replication_type   = var.account_replication_type
  container_names            = [var.input_container_name, var.output_container_name]
  diagnostic_services        = ["blob", "queue", "table"]
  log_analytics_workspace_id = module.log_analytics.id
  diagnostic_setting_name    = var.diagnostic_settings_name
  tags                       = var.tags
}

# Conditionally create a user-assigned identity for the function app
module "managed_identity" {
  source              = "./modules/managed_identity"
  count               = var.managed_identity_type == "UserAssigned" ? 1 : 0
  name                = local.managed_identity_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  tags                = var.tags
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
  identity_type                          = var.managed_identity_type
  identity_ids                           = var.managed_identity_type == "UserAssigned" ? [module.managed_identity[0].id] : []
  log_analytics_workspace_id             = module.log_analytics.id
  diagnostic_setting_name                = var.diagnostic_settings_name
  log_categories                         = var.log_categories
  metric_categories                      = var.metric_categories
  tags                                   = var.tags

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT                     = "true"
    ENABLE_ORYX_BUILD                                  = "true"
    AZURE_CLIENT_ID                                    = var.managed_identity_type == "UserAssigned" ? module.managed_identity[0].client_id : ""
    AzureWebJobsStorage                                = "DefaultEndpointsProtocol=https;AccountName=${module.storage_account.name};AccountKey=${module.storage_account.primary_access_key};EndpointSuffix=core.windows.net;"
    STORAGE_ACCOUNT_CONNECTION_STRING__blobServiceUri  = module.storage_account.primary_blob_endpoint
    STORAGE_ACCOUNT_CONNECTION_STRING__queueServiceUri = module.storage_account.primary_queue_endpoint
    STORAGE_ACCOUNT_CONNECTION_STRING__tableServiceUri = module.storage_account.primary_table_endpoint
    INPUT_STORAGE_CONTAINER_NAME                       = var.input_container_name
    OUTPUT_STORAGE_CONTAINER_NAME                      = var.output_container_name
    FUNCTIONS_WORKER_RUNTIME                           = var.runtime_name
    FUNCTIONS_EXTENSION_VERSION                        = "~4"
    # The Python worker sends its own telemetry through OpenTelemetry, which host.json turns on, instead of the host
    # forwarding its log records
    PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY = "true"
  }
}

# Assign the Storage Blob Data Contributor role on the storage account to the identity of the function app
module "storage_blob_data_contributor_role_assignment" {
  source               = "./modules/role_assignment"
  scope                = module.storage_account.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.principal_id
}

# Assign the Storage Queue Data Contributor role on the storage account to the identity of the function app
module "storage_queue_data_contributor_role_assignment" {
  source               = "./modules/role_assignment"
  scope                = module.storage_account.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = local.principal_id
}
