# Local Variables
locals {
  resource_group_name   = "${var.prefix}-rg"
  cosmosdb_account_name = "${var.prefix}-mongodb-${var.suffix}"
  app_service_plan_name = "${var.prefix}-app-service-plan-${var.suffix}"
  web_app_name          = "${var.prefix}-webapp-${var.suffix}"
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create a cosmosdb account
resource "azurerm_cosmosdb_account" "example" {
  name                       = local.cosmosdb_account_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  offer_type                 = "Standard"
  kind                       = "MongoDB"
  automatic_failover_enabled = false
  tags                       = var.tags

  consistency_policy {
    consistency_level       = var.consistency_level
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  geo_location {
    location          = var.primary_region
    failover_priority = 0
  }

  geo_location {
    location          = var.secondary_region
    failover_priority = 1
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_cosmosdb_mongo_database" "example" {
  name                = var.cosmosdb_database_name
  resource_group_name = azurerm_resource_group.example.name
  account_name        = azurerm_cosmosdb_account.example.name
  throughput          = 400
}

resource "azurerm_cosmosdb_mongo_collection" "example" {
  name                = var.cosmosdb_collection_name
  resource_group_name = azurerm_resource_group.example.name
  account_name        = azurerm_cosmosdb_account.example.name
  database_name       = azurerm_cosmosdb_mongo_database.example.name

  default_ttl_seconds = "777"
  shard_key           = "username"
  throughput          = 400

  # Dynamically create the 'index' blocks using a for_each loop over the variable
  dynamic "index" {
    # The for_each expression iterates over the list of keys from the variable
    for_each = var.mongodb_index_keys
    content {
      # The value of the current item in the iteration (e.g., "$**", "_id", etc.)
      keys = [index.value]
    }
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

# Create a web app
resource "azurerm_linux_web_app" "example" {
  name                          = local.web_app_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  service_plan_id               = azurerm_service_plan.example.id
  https_only                    = var.https_only
  public_network_access_enabled = var.public_network_access_enabled
  client_affinity_enabled       = false
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = var.always_on
    http2_enabled       = var.http2_enabled
    minimum_tls_version = var.minimum_tls_version
    application_stack {
      python_version = var.python_version
    }
  }

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    COSMOSDB_CONNECTION_STRING     = azurerm_cosmosdb_account.example.primary_mongodb_connection_string
    COSMOSDB_DATABASE_NAME         = azurerm_cosmosdb_mongo_database.example.name
    COSMOSDB_COLLECTION_NAME       = var.cosmosdb_collection_name
    LOGIN_NAME                     = var.login_name
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Deploy code from a public GitHub repo
resource "azurerm_app_service_source_control" "example" {
  count                  = var.repo_url == "" ? 0 : 1
  app_id                 = azurerm_linux_web_app.example.id
  repo_url               = var.repo_url
  branch                 = "main"
  use_manual_integration = true
  use_mercurial          = false
}