# =============================================================================
# Cold-path automation on Azure Event Hubs
#
# Capture archives the telemetry hub to Blob Storage; Event Hubs raises
# Microsoft.EventHub.CaptureFileCreated to an Event Grid system topic; a subscription with an
# event hub destination turns that into a stream; a Function App consumes it, decodes each
# archive and writes per-device summaries to a curated hub.
#
# Application code is published by deploy.sh, as in the other samples.
# =============================================================================

locals {
  prefix = lower(var.prefix)
  suffix = lower(var.suffix)
  # Storage and Key Vault style names take only the first four characters of the suffix, so the
  # three deployment paths (scripts, Bicep, Terraform) all produce the same names.
  suffix_short = substr(local.suffix, 0, min(4, length(local.suffix)))

  resource_group_name       = "${local.prefix}-ehgrid-rg"
  eventhub_namespace_name   = "${local.prefix}-ehns-${local.suffix}"
  storage_account_name      = substr(replace("${local.prefix}ehgrid${local.suffix_short}", "-", ""), 0, 24)
  function_app_name         = "${local.prefix}-ehgrid-processor"
  function_plan_name        = "${local.prefix}-ehgrid-plan"
  system_topic_name         = "${local.prefix}-ehns-systopic"
  log_analytics_name        = "${local.prefix}-ehgrid-log-analytics"
  application_insights_name = "${local.prefix}-ehgrid-insights"

  # The Functions host cannot parse the EndpointSuffix form when the suffix carries a port, which
  # it does against the emulator, so the endpoints are spelled out.
  storage_connection_string = join(";", [
    "DefaultEndpointsProtocol=https",
    "AccountName=${module.storage_account.name}",
    "AccountKey=${module.storage_account.primary_access_key}",
    "BlobEndpoint=${module.storage_account.primary_blob_endpoint}",
    "QueueEndpoint=${module.storage_account.primary_queue_endpoint}",
    "TableEndpoint=${module.storage_account.primary_table_endpoint}",
  ])
}

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# --------------------------------------------------------------------------- observability
module "log_analytics" {
  source              = "./modules/log_analytics"
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
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

# --------------------------------------------------------------------------- storage
module "storage_account" {
  source                     = "./modules/storage_account"
  name                       = local.storage_account_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  container_names            = [var.capture_container_name]
  diagnostic_services        = ["blob", "queue", "table"]
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags
}

# --------------------------------------------------------------------------- event hubs
module "event_hubs" {
  source                     = "./modules/event_hubs"
  name                       = local.eventhub_namespace_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  sku                        = var.eventhub_sku
  telemetry_hub_name         = var.telemetry_hub_name
  notification_hub_name      = var.notification_hub_name
  curated_hub_name           = var.curated_hub_name
  telemetry_partition_count  = var.telemetry_partition_count
  retention_days             = var.retention_days
  capture_interval_seconds   = var.capture_interval_seconds
  capture_size_limit_bytes   = var.capture_size_limit_bytes
  capture_container_name     = module.storage_account.container_names[0]
  capture_storage_account_id = module.storage_account.id
  capture_consumer_group     = var.capture_consumer_group
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags
}

# --------------------------------------------------------------------------- event grid
module "event_grid" {
  source                     = "./modules/event_grid"
  name                       = local.system_topic_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  source_resource_id         = module.event_hubs.id
  subscription_name          = var.event_subscription_name
  eventhub_id                = module.event_hubs.notification_hub_id
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags
}

# --------------------------------------------------------------------------- workloads
module "app_service_plan" {
  source                     = "./modules/app_service_plan"
  name                       = local.function_plan_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  os_type                    = "Linux"
  sku_name                   = "Y1"
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags
}

module "function_app" {
  source                                 = "./modules/function_app"
  name                                   = local.function_app_name
  resource_group_name                    = azurerm_resource_group.main.name
  location                               = azurerm_resource_group.main.location
  service_plan_id                        = module.app_service_plan.id
  storage_account_name                   = module.storage_account.name
  storage_account_access_key             = module.storage_account.primary_access_key
  https_only                             = true
  always_on                              = false
  application_insights_connection_string = module.application_insights.connection_string
  python_version                         = var.python_version
  log_analytics_workspace_id             = module.log_analytics.id
  tags                                   = var.tags

  app_settings = {
    AzureWebJobsStorage                      = local.storage_connection_string
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING = local.storage_connection_string
    STORAGE_CONNECTION_STRING                = local.storage_connection_string
    # The processor imports fastavro and azure-storage-blob to decode an archive, so the
    # deployment has to run a build that installs requirements.txt. Without these the package is
    # copied as-is and the imports fail at invocation time.
    ENABLE_ORYX_BUILD              = "true"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    # Namespace-level on purpose: an entity-level connection string carries EntityPath, which
    # would pin the output binding to the notifications hub instead of the curated one.
    EVENTHUB_NOTIFICATION_CONNECTION = module.event_hubs.namespace_connection_string
    EVENTHUB_CURATED_CONNECTION      = module.event_hubs.namespace_connection_string
    NOTIFICATION_HUB_NAME            = module.event_hubs.notification_hub_name
    CURATED_HUB_NAME                 = module.event_hubs.curated_hub_name
    CAPTURE_CONSUMER_GROUP           = module.event_hubs.capture_consumer_group
    TEMPERATURE_LIMIT                = tostring(var.temperature_limit)
    FUNCTIONS_WORKER_RUNTIME         = "python"
  }
}
