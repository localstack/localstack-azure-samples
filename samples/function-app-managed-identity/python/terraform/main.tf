# Local Variables
locals {
  resource_group_name   = "${var.prefix}-rg"
  storage_account_name  = "${var.prefix}storage${var.suffix}"
  app_service_plan_name = "${var.prefix}-app-service-plan-${var.suffix}"
  function_app_name     = "${var.prefix}-functionapp-${var.suffix}"
  managed_identity_name = "${var.prefix}-identity-${var.suffix}"
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

# Create input storage container
resource "azurerm_storage_container" "input" {
  name                  = var.input_container_name
  storage_account_id    = azurerm_storage_account.example.id
  container_access_type = "private"
}

# Create output storage container
resource "azurerm_storage_container" "output" {
  name                  = var.output_container_name
  storage_account_id    = azurerm_storage_account.example.id
  container_access_type = "private"
}

# Conditionally create a user assigned identity for the function app
resource "azurerm_user_assigned_identity" "identity" {
  count = var.managed_identity_type == "UserAssigned" ? 1 : 0

  name                = local.managed_identity_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
}

# Assign Storage Blob Data Contributor role to the function app identity
resource "azurerm_role_assignment" "blob_contributor" {
  scope                = azurerm_storage_account.example.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.managed_identity_type == "UserAssigned" ? azurerm_user_assigned_identity.identity[0].principal_id : azurerm_linux_function_app.example.identity[0].principal_id
}

# Assign Storage Queue Data Contributor role to the function app identity
resource "azurerm_role_assignment" "queue_contributor" {
  scope                = azurerm_storage_account.example.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = var.managed_identity_type == "UserAssigned" ? azurerm_user_assigned_identity.identity[0].principal_id : azurerm_linux_function_app.example.identity[0].principal_id
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
    type = var.managed_identity_type
    identity_ids = var.managed_identity_type == "UserAssigned" ? [
      azurerm_user_assigned_identity.identity[0].id
    ] : []
  }

  site_config {
    always_on           = var.always_on
    minimum_tls_version = var.minimum_tls_version
    application_stack {
      python_version = var.python_version
    }
  }

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT                     = "true"
    ENABLE_ORYX_BUILD                                  = "true"
    AZURE_CLIENT_ID                                    = var.managed_identity_type == "UserAssigned" ? azurerm_user_assigned_identity.identity[0].client_id : ""
    AzureWebJobsStorage                                = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};EndpointSuffix=core.windows.net;"
    STORAGE_ACCOUNT_CONNECTION_STRING__blobServiceUri  = azurerm_storage_account.example.primary_blob_endpoint
    STORAGE_ACCOUNT_CONNECTION_STRING__queueServiceUri = azurerm_storage_account.example.primary_queue_endpoint
    STORAGE_ACCOUNT_CONNECTION_STRING__tableServiceUri = azurerm_storage_account.example.primary_table_endpoint
    INPUT_STORAGE_CONTAINER_NAME                       = var.input_container_name
    OUTPUT_STORAGE_CONTAINER_NAME                      = var.output_container_name
    FUNCTIONS_WORKER_RUNTIME                           = var.runtime_name
    FUNCTIONS_EXTENSION_VERSION                        = "~4"
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