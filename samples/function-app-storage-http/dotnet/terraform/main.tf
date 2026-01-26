# Local Variables
locals {
  storage_account_name  = "${var.prefix}storage${var.suffix}"
  app_service_plan_name = "${var.prefix}-app-service-plan-${var.suffix}"
  function_app_name     = "${var.prefix}-functionapp-${var.suffix}"
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
    minimum_tls_version = var.minimum_tls_version
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
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING  = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};EndpointSuffix=core.windows.net;"
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

# Create an app source control configuration
resource "azurerm_app_service_source_control" "example" {
  count    = var.repo_url == "" ? 0 : 1
  app_id   = azurerm_linux_function_app.example.id
  repo_url = var.repo_url
  branch   = "main"
}