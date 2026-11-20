# Local Variables
locals {
  resource_group_name       = "${var.prefix}-rg"
  storage_account_name      = "${var.prefix}invstorage${var.suffix}"
  app_service_plan          = "${var.prefix}-inventory-app-service-plan-${var.suffix}"
  function_app_name         = "${var.prefix}-inventory-functionapp-${var.suffix}"
  apim_name                 = "${var.prefix}-inventory-apim-${var.suffix}"
  log_analytics_name        = "${var.prefix}-log-analytics-${var.suffix}"
  application_insights_name = "${var.prefix}-insights-${var.suffix}"
}

# The shared secret the gateway adds to every backend call. The Function App checks it, and the
# gateway reads it from a secret named value, so neither the policy document nor any client ever
# contains it.
resource "random_password" "backend_secret" {
  length  = 32
  special = false
}

# ---------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# Monitoring: the workspace and Application Insights
# ---------------------------------------------------------------------------
module "log_analytics" {
  source              = "./modules/log_analytics"
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_in_days
  tags                = var.tags
}

module "application_insights" {
  source              = "./modules/application_insights"
  name                = local.application_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = module.log_analytics.id
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Function App: the Inventory backend
# ---------------------------------------------------------------------------
# The storage account of the Functions host, whose blob, queue and table services send their logs to the workspace
module "storage_account" {
  source                     = "./modules/storage_account"
  name                       = local.storage_account_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  diagnostic_services        = ["blob", "queue", "table"]
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags
}

module "app_service_plan" {
  source                     = "./modules/app_service_plan"
  name                       = local.app_service_plan
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  sku_name                   = var.app_service_plan_sku
  os_type                    = "Linux"
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags
}

module "function_app" {
  source                     = "./modules/function_app"
  name                       = local.function_app_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = module.app_service_plan.id
  storage_account_name       = module.storage_account.name
  storage_account_access_key = module.storage_account.primary_access_key
  # On a Dedicated (App Service) plan the Functions host goes idle without this, and a gateway call then waits for a
  # cold start
  always_on                              = true
  application_insights_connection_string = module.application_insights.connection_string
  python_version                         = var.python_version
  log_analytics_workspace_id             = module.log_analytics.id
  tags                                   = var.tags

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME       = "python"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"
    # The Functions host parses AzureWebJobsStorage with the strict .NET storage clients, which
    # cannot parse the EndpointSuffix-with-port string the provider would compose on the
    # emulator - so the provider default is overridden with an explicit-endpoints connection,
    # as the url-shortener sibling does.
    AzureWebJobsStorage = "DefaultEndpointsProtocol=https;AccountName=${module.storage_account.name};AccountKey=${module.storage_account.primary_access_key};BlobEndpoint=${module.storage_account.primary_blob_endpoint};QueueEndpoint=${module.storage_account.primary_queue_endpoint};TableEndpoint=${module.storage_account.primary_table_endpoint}"
    # The same secret the gateway injects from its named value.
    BACKEND_SECRET = random_password.backend_secret.result
    # The Python worker sends its own telemetry through OpenTelemetry, which host.json turns on, instead of the host
    # forwarding its log records, and only the records of the function's logger
    PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY = "true"
    PYTHON_APPLICATIONINSIGHTS_LOGGER_NAME      = "function_app"
  }
}

# ---------------------------------------------------------------------------
# API Management
# ---------------------------------------------------------------------------
module "api_management" {
  source              = "./modules/api_management"
  name                = local.apim_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.apim_sku_name
  backend_secret      = random_password.backend_secret.result
  # The backend is the Function App: the emulator answers on plain HTTP under its own hostname (use https:// on real
  # Azure)
  service_url                = "${var.backend_scheme}://${module.function_app.default_hostname}/api"
  open_api_document          = file("${path.module}/../apim/openapi.json")
  api_policy                 = file("${path.module}/../apim/inventory-api-policy.xml")
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags
}
