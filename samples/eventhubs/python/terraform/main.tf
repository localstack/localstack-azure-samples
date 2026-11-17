# =============================================================================
# Real-time payment fraud detection on Azure Event Hubs
#
# Event Hubs (Capture, Kafka, schema group, least-privilege rules), Storage,
# Key Vault, monitoring, an Event Hubs-triggered Function App and the dashboard
# Web App, each created by a module with its diagnostic settings. Application
# code is deployed by deploy.sh after terraform apply.
# =============================================================================

locals {
  prefix = lower(var.prefix)
  suffix = lower(var.suffix)
  # Storage and Key Vault names take only the first four characters of the suffix, matching
  # `${SUFFIX:0:4}` in scripts/deploy.sh and `take(suffix, 4)` in the Bicep template, so all
  # three deployment paths produce the same names and scripts/validate.sh applies to each.
  suffix_short = substr(local.suffix, 0, min(4, length(local.suffix)))

  resource_group_name     = "${local.prefix}-eventhubs-rg"
  eventhub_namespace_name = "${local.prefix}-ehns-${local.suffix}"
  storage_account_name    = substr(replace("${local.prefix}ehstorage${local.suffix_short}", "-", ""), 0, 24)
  key_vault_name          = substr(replace("${local.prefix}ehkv${local.suffix_short}", "-", ""), 0, 24)
  workspace_name          = "${local.prefix}-eh-logs"
  app_insights_name       = "${local.prefix}-eh-insights"
  function_app_name       = "${local.prefix}-eh-fraud-func"
  web_app_name            = "${local.prefix}-eh-dashboard"
  function_plan_name      = "${local.prefix}-eh-func-plan"
  web_plan_name           = "${local.prefix}-eh-plan"
  fraud_consumer_group    = var.consumer_groups[0]

  # Built from the account's own endpoints rather than the EndpointSuffix form the provider
  # exposes as primary_connection_string. Both are valid against Azure, but only this one
  # survives a non-default port, which the Azure Functions host (a .NET workload) needs in
  # order to parse AzureWebJobsStorage at all.
  storage_connection_string = join(";", [
    "DefaultEndpointsProtocol=https",
    "AccountName=${module.storage_account.name}",
    "AccountKey=${module.storage_account.primary_access_key}",
    "BlobEndpoint=${module.storage_account.primary_blob_endpoint}",
    "QueueEndpoint=${module.storage_account.primary_queue_endpoint}",
    "TableEndpoint=${module.storage_account.primary_table_endpoint}",
  ])
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# -----------------------------------------------------------------------------
# Monitoring: the workspace and the Application Insights resource the two apps send their telemetry to
# -----------------------------------------------------------------------------
module "log_analytics" {
  source              = "./modules/log_analytics"
  name                = local.workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

module "application_insights" {
  source              = "./modules/application_insights"
  name                = local.app_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = module.log_analytics.id
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Storage: Capture archives, Function App checkpoints and content
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Event Hubs: the streaming backbone
# -----------------------------------------------------------------------------
module "event_hubs" {
  source                      = "./modules/event_hubs"
  name                        = local.eventhub_namespace_name
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  sku                         = var.eventhub_sku
  capacity                    = var.eventhub_capacity
  maximum_throughput_units    = var.eventhub_maximum_throughput_units
  event_hub_name              = var.event_hub_name
  alert_hub_name              = var.alert_hub_name
  partition_count             = var.partition_count
  alert_partition_count       = var.alert_partition_count
  message_retention_days      = var.message_retention_days
  consumer_groups             = var.consumer_groups
  capture_container_name      = module.storage_account.container_names[0]
  capture_storage_account_id  = module.storage_account.id
  capture_interval_in_seconds = var.capture_interval_in_seconds
  capture_size_limit_in_bytes = var.capture_size_limit_in_bytes
  schema_group_name           = var.schema_group_name
  log_analytics_workspace_id  = module.log_analytics.id
  tags                        = var.tags
}

# -----------------------------------------------------------------------------
# Key Vault: connection strings belong in a vault, not in app settings
# -----------------------------------------------------------------------------
module "key_vault" {
  source                     = "./modules/key_vault"
  name                       = local.key_vault_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  rbac_authorization_enabled = true
  deployer_object_id         = var.deployer_object_id
  deployer_principal_type    = var.deployer_principal_type
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags

  # The storage secret holds the explicit-endpoint form, the same as the CLI and Bicep paths: the provider's
  # primary_connection_string uses EndpointSuffix, which the Functions host cannot parse when the suffix carries a port.
  secrets = {
    "eventhub-send-connection"   = module.event_hubs.send_connection_string
    "eventhub-listen-connection" = module.event_hubs.listen_connection_string
    "storage-connection"         = local.storage_connection_string
  }
}

# -----------------------------------------------------------------------------
# Workloads: the Event Hubs-triggered processor and the dashboard
# -----------------------------------------------------------------------------
module "function_plan" {
  source                     = "./modules/app_service_plan"
  name                       = local.function_plan_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  os_type                    = "Linux"
  sku_name                   = "Y1"
  diagnostic_setting_name    = "default"
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags
}

module "function_app" {
  source                                 = "./modules/function_app"
  name                                   = local.function_app_name
  resource_group_name                    = azurerm_resource_group.main.name
  location                               = azurerm_resource_group.main.location
  service_plan_id                        = module.function_plan.id
  storage_account_name                   = module.storage_account.name
  storage_account_access_key             = module.storage_account.primary_access_key
  always_on                              = false
  application_insights_connection_string = module.application_insights.connection_string
  python_version                         = var.python_version
  log_analytics_workspace_id             = module.log_analytics.id
  tags                                   = var.tags

  # The trigger and output bindings resolve these settings by name (function_app.py).
  app_settings = {
    AzureWebJobsStorage           = local.storage_connection_string
    EVENTHUB_LISTEN_CONNECTION    = module.event_hubs.listen_connection_string
    EVENTHUB_SEND_CONNECTION      = module.event_hubs.alert_send_connection_string
    EVENT_HUB_NAME                = module.event_hubs.event_hub_name
    ALERT_HUB_NAME                = module.event_hubs.alert_hub_name
    FRAUD_CONSUMER_GROUP          = local.fraud_consumer_group
    FRAUD_AMOUNT_THRESHOLD        = tostring(var.fraud_amount_threshold)
    FRAUD_VELOCITY_COUNT          = tostring(var.fraud_velocity_count)
    FRAUD_VELOCITY_WINDOW_SECONDS = tostring(var.fraud_velocity_window_seconds)
    # With telemetryMode set to OpenTelemetry in host.json, the Python worker sends the records of the function's
    # logger, its exceptions, custom events and custom metrics to Application Insights
    PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY = "true"
    PYTHON_APPLICATIONINSIGHTS_LOGGER_NAME      = "function_app"
  }
}

module "web_plan" {
  source                     = "./modules/app_service_plan"
  name                       = local.web_plan_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  os_type                    = "Linux"
  sku_name                   = "S1"
  diagnostic_setting_name    = "default"
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags
}

# The dashboard has no app_command_line: App Service starts Gunicorn for the Flask app in app.py, and Gunicorn reads
# gunicorn.conf.py from the app folder. With a custom command, the container that starts before the package is
# deployed exits at once ('gunicorn.conf.py' doesn't exist)
module "web_app" {
  source                     = "./modules/web_app"
  name                       = local.web_app_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = module.web_plan.location
  service_plan_id            = module.web_plan.id
  python_version             = var.python_version
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags

  # The dashboard sends its telemetry through the Microsoft OpenTelemetry Distro, which reads the connection string
  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT        = "true"
    EVENTHUB_LISTEN_CONNECTION_STRING     = module.event_hubs.dashboard_listen_connection_string
    STORAGE_CONNECTION_STRING             = local.storage_connection_string
    EVENT_HUB_NAME                        = module.event_hubs.event_hub_name
    ALERT_HUB_NAME                        = module.event_hubs.alert_hub_name
    FRAUD_CONSUMER_GROUP                  = local.fraud_consumer_group
    CAPTURE_CONTAINER_NAME                = module.storage_account.container_names[0]
    SCHEMA_GROUP_NAME                     = module.event_hubs.schema_group_name
    APPLICATIONINSIGHTS_CONNECTION_STRING = module.application_insights.connection_string
  }
}
