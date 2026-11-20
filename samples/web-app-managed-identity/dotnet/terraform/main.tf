# Local Variables
locals {
  resource_group_name       = "${var.prefix}-rg"
  storage_account_name      = "${var.prefix}storage${var.suffix}"
  app_service_plan_name     = "${var.prefix}-app-service-plan-${var.suffix}"
  web_app_name              = "${var.prefix}-webapp-${var.suffix}"
  managed_identity_name     = "${var.prefix}-identity-${var.suffix}"
  log_analytics_name        = "${var.prefix}-log-analytics-${var.suffix}"
  application_insights_name = "${var.prefix}-insights-${var.suffix}"
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create the Log Analytics workspace that receives the logs and metrics of the resources and the telemetry of the web app
module "log_analytics" {
  source              = "./modules/log_analytics"
  name                = local.log_analytics_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  tags                = var.tags
}

# Create the workspace-based Application Insights component that collects the web app's requests, dependencies, logs, exceptions, custom events and custom metrics
module "application_insights" {
  source              = "./modules/application_insights"
  name                = local.application_insights_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  workspace_id        = module.log_analytics.id
  tags                = var.tags
}

# Create the storage account, its blob container and the diagnostic settings of the account and of its blob service
module "storage_account" {
  source                     = "./modules/storage_account"
  name                       = local.storage_account_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  account_kind               = var.account_kind
  account_tier               = var.account_tier
  account_replication_type   = var.account_replication_type
  container_names            = [var.storage_container_name]
  log_analytics_workspace_id = module.log_analytics.id
  diagnostic_setting_name    = var.diagnostic_settings_name
  tags                       = var.tags
}

# Conditionally create a user-assigned identity for the web app
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

# Create the web app and its diagnostic setting
module "web_app" {
  source                        = "./modules/web_app"
  name                          = local.web_app_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  service_plan_id               = module.app_service_plan.id
  https_only                    = var.https_only
  public_network_access_enabled = var.webapp_public_network_access_enabled
  always_on                     = var.always_on
  http2_enabled                 = var.http2_enabled
  minimum_tls_version           = var.minimum_tls_version
  dotnet_version                = var.dotnet_version
  identity_type                 = var.managed_identity_type
  identity_ids                  = var.managed_identity_type == "UserAssigned" ? [module.managed_identity[0].id] : []
  log_analytics_workspace_id    = module.log_analytics.id
  diagnostic_setting_name       = var.diagnostic_settings_name
  log_categories                = var.log_categories
  metric_categories             = var.metric_categories
  tags                          = var.tags

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT        = "true"
    ENABLE_ORYX_BUILD                     = "true"
    AZURE_STORAGE_ACCOUNT_URL             = module.storage_account.primary_blob_endpoint
    CONTAINER_NAME                        = var.storage_container_name
    AZURE_CLIENT_ID                       = var.managed_identity_type == "UserAssigned" ? module.managed_identity[0].client_id : ""
    APPLICATIONINSIGHTS_CONNECTION_STRING = module.application_insights.connection_string
  }
}

# Assign the Storage Blob Data Contributor role on the storage account to the identity of the web app
module "storage_blob_data_contributor_role_assignment" {
  source               = "./modules/role_assignment"
  scope                = module.storage_account.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.managed_identity_type == "UserAssigned" ? module.managed_identity[0].principal_id : module.web_app.principal_id
}
