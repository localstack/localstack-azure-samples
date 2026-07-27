# =============================================================================
# Real-time payment fraud detection on Azure Event Hubs
#
# Event Hubs (Capture, Kafka, schema group, least-privilege rules), Storage,
# Key Vault, monitoring, an Event Hubs-triggered Function App and the dashboard
# Web App. Application code is deployed by deploy.sh after terraform apply.
# =============================================================================

locals {
  # Built from the account's own endpoints rather than the EndpointSuffix form the provider
  # exposes as primary_connection_string. Both are valid against Azure, but only this one
  # survives a non-default port, which the Azure Functions host (a .NET workload) needs in
  # order to parse AzureWebJobsStorage at all.
  storage_connection_string = join(";", [
    "DefaultEndpointsProtocol=https",
    "AccountName=${azurerm_storage_account.main.name}",
    "AccountKey=${azurerm_storage_account.main.primary_access_key}",
    "BlobEndpoint=${azurerm_storage_account.main.primary_blob_endpoint}",
    "QueueEndpoint=${azurerm_storage_account.main.primary_queue_endpoint}",
    "TableEndpoint=${azurerm_storage_account.main.primary_table_endpoint}",
  ])

  prefix                  = lower(var.prefix)
  suffix                  = lower(var.suffix)
  resource_group_name     = "${local.prefix}-eventhubs-rg"
  eventhub_namespace_name = "${local.prefix}-ehns-${local.suffix}"
  storage_account_name    = substr(replace("${local.prefix}ehstorage${local.suffix}", "-", ""), 0, 24)
  key_vault_name          = substr(replace("${local.prefix}ehkv${local.suffix}", "-", ""), 0, 24)
  workspace_name          = "${local.prefix}-eh-logs"
  app_insights_name       = "${local.prefix}-eh-insights"
  function_app_name       = "${local.prefix}-eh-fraud-func"
  web_app_name            = "${local.prefix}-eh-dashboard"
  function_plan_name      = "${local.prefix}-eh-func-plan"
  web_plan_name           = "${local.prefix}-eh-plan"
  fraud_consumer_group    = var.consumer_groups[0]
}

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# -----------------------------------------------------------------------------
# Storage: Capture archives, Function App checkpoints and content
# -----------------------------------------------------------------------------
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_storage_container" "capture" {
  name                  = var.capture_container_name
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.workspace_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "main" {
  name                = local.app_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Event Hubs: the streaming backbone
# -----------------------------------------------------------------------------
resource "azurerm_eventhub_namespace" "main" {
  name                     = local.eventhub_namespace_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  sku                      = var.eventhub_sku
  capacity                 = var.eventhub_capacity
  auto_inflate_enabled     = true
  maximum_throughput_units = var.eventhub_maximum_throughput_units
  minimum_tls_version      = "1.2"
  tags                     = var.tags
}

# The payments hub archives itself to Blob Storage as Avro: the cold path needs no
# consumer code at all.
resource "azurerm_eventhub" "payments" {
  name              = var.event_hub_name
  namespace_id      = azurerm_eventhub_namespace.main.id
  partition_count   = var.partition_count
  message_retention = var.message_retention_days

  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = var.capture_interval_in_seconds
    size_limit_in_bytes = var.capture_size_limit_in_bytes
    skip_empty_archives = true

    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.capture.name
      storage_account_id  = azurerm_storage_account.main.id
    }
  }
}

resource "azurerm_eventhub" "alerts" {
  name              = var.alert_hub_name
  namespace_id      = azurerm_eventhub_namespace.main.id
  partition_count   = var.alert_partition_count
  message_retention = var.message_retention_days
}

# Each downstream system reads the same log at its own pace, with its own offsets.
resource "azurerm_eventhub_consumer_group" "groups" {
  for_each = toset(var.consumer_groups)

  name                = each.value
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.payments.name
  resource_group_name = azurerm_resource_group.main.name
}

# Least privilege: producers may only Send, consumers may only Listen.
resource "azurerm_eventhub_authorization_rule" "send" {
  name                = "payments-send"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.payments.name
  resource_group_name = azurerm_resource_group.main.name

  listen = false
  send   = true
  manage = false
}

resource "azurerm_eventhub_authorization_rule" "listen" {
  name                = "payments-listen"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.payments.name
  resource_group_name = azurerm_resource_group.main.name

  listen = true
  send   = false
  manage = false
}

resource "azurerm_eventhub_authorization_rule" "alerts_send" {
  name                = "alerts-send"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.alerts.name
  resource_group_name = azurerm_resource_group.main.name

  listen = false
  send   = true
  manage = false
}

# The versioned contract producers and consumers agree on.
resource "azurerm_eventhub_namespace_schema_group" "payments" {
  name                 = var.schema_group_name
  namespace_id         = azurerm_eventhub_namespace.main.id
  schema_compatibility = "Forward"
  schema_type          = "Avro"
}

# -----------------------------------------------------------------------------
# Key Vault: connection strings belong in a vault, not in app settings
# -----------------------------------------------------------------------------
resource "azurerm_key_vault" "main" {
  name                       = local.key_vault_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  tenant_id                  = "00000000-0000-0000-0000-000000000000"
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = var.tags
}

resource "azurerm_key_vault_secret" "eventhub_send" {
  name         = "eventhub-send-connection"
  value        = azurerm_eventhub_authorization_rule.send.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "eventhub_listen" {
  name         = "eventhub-listen-connection"
  value        = azurerm_eventhub_authorization_rule.listen.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "storage" {
  name         = "storage-connection"
  value        = azurerm_storage_account.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
}

# -----------------------------------------------------------------------------
# Workloads: the Event Hubs-triggered processor and the dashboard
# -----------------------------------------------------------------------------
resource "azurerm_service_plan" "functions" {
  name                = local.function_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = var.tags
}

resource "azurerm_linux_function_app" "fraud" {
  name                       = local.function_app_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = azurerm_service_plan.functions.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  tags                       = var.tags

  site_config {
    application_insights_connection_string = azurerm_application_insights.main.connection_string

    application_stack {
      python_version = var.python_version
    }
  }

  # The trigger and output bindings resolve these settings by name (function_app.py).
  app_settings = {
    AzureWebJobsStorage           = local.storage_connection_string
    EVENTHUB_LISTEN_CONNECTION    = azurerm_eventhub_authorization_rule.listen.primary_connection_string
    EVENTHUB_SEND_CONNECTION      = azurerm_eventhub_authorization_rule.alerts_send.primary_connection_string
    EVENT_HUB_NAME                = azurerm_eventhub.payments.name
    ALERT_HUB_NAME                = azurerm_eventhub.alerts.name
    FRAUD_CONSUMER_GROUP          = local.fraud_consumer_group
    FRAUD_AMOUNT_THRESHOLD        = tostring(var.fraud_amount_threshold)
    FRAUD_VELOCITY_COUNT          = tostring(var.fraud_velocity_count)
    FRAUD_VELOCITY_WINDOW_SECONDS = tostring(var.fraud_velocity_window_seconds)
  }
}

resource "azurerm_service_plan" "web" {
  name                = local.web_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "S1"
  tags                = var.tags
}

resource "azurerm_linux_web_app" "dashboard" {
  name                = local.web_app_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.web.location
  service_plan_id     = azurerm_service_plan.web.id
  tags                = var.tags

  site_config {
    app_command_line = "gunicorn --config gunicorn.conf.py app:app"

    application_stack {
      python_version = var.python_version
    }
  }

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT        = "true"
    EVENTHUB_LISTEN_CONNECTION_STRING     = azurerm_eventhub_namespace.main.default_primary_connection_string
    STORAGE_CONNECTION_STRING             = local.storage_connection_string
    EVENT_HUB_NAME                        = azurerm_eventhub.payments.name
    ALERT_HUB_NAME                        = azurerm_eventhub.alerts.name
    FRAUD_CONSUMER_GROUP                  = local.fraud_consumer_group
    CAPTURE_CONTAINER_NAME                = azurerm_storage_container.capture.name
    SCHEMA_GROUP_NAME                     = var.schema_group_name
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
  }
}
