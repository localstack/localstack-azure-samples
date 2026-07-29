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

  resource_group_name     = "${local.prefix}-ehgrid-rg"
  eventhub_namespace_name = "${local.prefix}-ehns-${local.suffix}"
  storage_account_name    = substr(replace("${local.prefix}ehgrid${local.suffix_short}", "-", ""), 0, 24)
  function_app_name       = "${local.prefix}-ehgrid-processor"
  function_plan_name      = "${local.prefix}-ehgrid-plan"
  system_topic_name       = "${local.prefix}-ehns-systopic"

  # The Functions host cannot parse the EndpointSuffix form when the suffix carries a port, which
  # it does against the emulator, so the endpoints are spelled out.
  storage_connection_string = join(";", [
    "DefaultEndpointsProtocol=https",
    "AccountName=${azurerm_storage_account.main.name}",
    "AccountKey=${azurerm_storage_account.main.primary_access_key}",
    "BlobEndpoint=${azurerm_storage_account.main.primary_blob_endpoint}",
    "QueueEndpoint=${azurerm_storage_account.main.primary_queue_endpoint}",
    "TableEndpoint=${azurerm_storage_account.main.primary_table_endpoint}",
  ])
}

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# --------------------------------------------------------------------------- storage
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}

resource "azurerm_storage_container" "capture" {
  name                  = var.capture_container_name
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

# --------------------------------------------------------------------------- event hubs
resource "azurerm_eventhub_namespace" "main" {
  name                = local.eventhub_namespace_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.eventhub_sku
  capacity            = 1
  tags                = var.tags
}

# The hub Capture archives. skip_empty_archives keeps Event Hubs from raising a
# CaptureFileCreated for a window that saw no readings.
resource "azurerm_eventhub" "telemetry" {
  name              = var.telemetry_hub_name
  namespace_id      = azurerm_eventhub_namespace.main.id
  partition_count   = var.telemetry_partition_count
  message_retention = var.retention_days

  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = var.capture_interval_seconds
    size_limit_in_bytes = var.capture_size_limit_bytes
    skip_empty_archives = true

    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.capture.name
      storage_account_id  = azurerm_storage_account.main.id
    }
  }
}

resource "azurerm_eventhub" "notifications" {
  name              = var.notification_hub_name
  namespace_id      = azurerm_eventhub_namespace.main.id
  partition_count   = 2
  message_retention = var.retention_days
}

resource "azurerm_eventhub" "curated" {
  name              = var.curated_hub_name
  namespace_id      = azurerm_eventhub_namespace.main.id
  partition_count   = 2
  message_retention = var.retention_days
}

# The processor keeps its own position in the notifications stream.
resource "azurerm_eventhub_consumer_group" "capture_processor" {
  name                = var.capture_consumer_group
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.notifications.name
  resource_group_name = azurerm_resource_group.main.name
}

# Least privilege: producers may only Send to the telemetry hub.
resource "azurerm_eventhub_authorization_rule" "telemetry_send" {
  name                = "telemetry-send"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.telemetry.name
  resource_group_name = azurerm_resource_group.main.name

  listen = false
  send   = true
  manage = false
}

# The demo scripts read all three hubs, so this rule is namespace-wide - but Listen only.
resource "azurerm_eventhub_namespace_authorization_rule" "pipeline_listen" {
  name                = "pipeline-listen"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name

  listen = true
  send   = false
  manage = false
}

# --------------------------------------------------------------------------- event grid
# A system topic is how a subscriber reaches the events a resource raises about itself; Event Hubs
# raises exactly one, Microsoft.EventHub.CaptureFileCreated.
resource "azurerm_eventgrid_system_topic" "namespace" {
  name                   = local.system_topic_name
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  source_arm_resource_id = azurerm_eventhub_namespace.main.id
  topic_type             = "Microsoft.Eventhub.Namespaces"
  tags                   = var.tags
}

# Delivering to an event hub turns the notification into a stream event, so an ordinary Event Hubs
# trigger can consume it: no public webhook, and a durable backlog if the processor is down.
resource "azurerm_eventgrid_system_topic_event_subscription" "capture_to_eventhub" {
  name                  = var.event_subscription_name
  system_topic          = azurerm_eventgrid_system_topic.namespace.name
  resource_group_name   = azurerm_resource_group.main.name
  eventhub_endpoint_id  = azurerm_eventhub.notifications.id
  event_delivery_schema = "EventGridSchema"
}

# --------------------------------------------------------------------------- workloads
resource "azurerm_service_plan" "functions" {
  name                = local.function_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = var.tags
}

resource "azurerm_linux_function_app" "processor" {
  name                       = local.function_app_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = azurerm_service_plan.functions.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  tags                       = var.tags

  site_config {
    application_stack {
      python_version = var.python_version
    }
  }

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
    EVENTHUB_NOTIFICATION_CONNECTION = azurerm_eventhub_namespace.main.default_primary_connection_string
    EVENTHUB_CURATED_CONNECTION      = azurerm_eventhub_namespace.main.default_primary_connection_string
    NOTIFICATION_HUB_NAME            = azurerm_eventhub.notifications.name
    CURATED_HUB_NAME                 = azurerm_eventhub.curated.name
    CAPTURE_CONSUMER_GROUP           = azurerm_eventhub_consumer_group.capture_processor.name
    TEMPERATURE_LIMIT                = tostring(var.temperature_limit)
  }
}
