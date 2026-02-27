resource "azurerm_cosmosdb_account" "example" {
  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  offer_type                 = "Standard"
  kind                       = "MongoDB"
  mongo_server_version       = var.mongo_server_version
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
  name                = var.database_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.example.name
  throughput          = var.database_throughput
}

resource "azurerm_cosmosdb_mongo_collection" "example" {
  name                = var.collection_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.example.name
  database_name       = azurerm_cosmosdb_mongo_database.example.name

  default_ttl_seconds = var.default_ttl_seconds
  shard_key           = var.shard_key
  throughput          = var.collection_throughput

  # Dynamically create the 'index' blocks using a for_each loop over the variable
  dynamic "index" {
    # The for_each expression iterates over the list of keys from the variable
    for_each = var.index_keys
    content {
      # The value of the current item in the iteration (e.g., "$**", "_id", etc.)
      keys = [index.value]
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "example" {
  name                       = "DiagnosticsSettings"
  target_resource_id         = azurerm_cosmosdb_account.example.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "DataPlaneRequests"
  }

  enabled_log {
    category = "MongoRequests"
  }

  enabled_metric {
    category = "Requests"
  }
}