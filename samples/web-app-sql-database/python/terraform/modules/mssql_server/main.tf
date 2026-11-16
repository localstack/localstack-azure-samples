resource "azurerm_mssql_server" "example" {
  name                                 = var.name
  resource_group_name                  = var.resource_group_name
  location                             = var.location
  administrator_login                  = var.administrator_login
  administrator_login_password         = var.administrator_login_password
  minimum_tls_version                  = var.minimum_tls_version
  public_network_access_enabled        = var.public_network_access_enabled
  outbound_network_restriction_enabled = var.outbound_network_restriction_enabled
  version                              = var.sql_version
  primary_user_assigned_identity_id    = var.managed_identity_id
  tags                                 = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  # The TDE protector is managed by the transparent_data_encryption module
  lifecycle {
    ignore_changes = [
      tags,
      transparent_data_encryption_key_vault_key_id
    ]
  }
}

resource "azurerm_mssql_firewall_rule" "example" {
  name             = var.firewall_rule_name
  server_id        = azurerm_mssql_server.example.id
  start_ip_address = var.start_ip_address
  end_ip_address   = var.end_ip_address
}

resource "azurerm_mssql_database" "example" {
  name                        = var.database_name
  server_id                   = azurerm_mssql_server.example.id
  sku_name                    = var.sku_name
  auto_pause_delay_in_minutes = var.auto_pause_delay
  collation                   = var.collation
  create_mode                 = var.create_mode
  elastic_pool_id             = var.elastic_pool_id
  max_size_gb                 = var.max_size_gb
  min_capacity                = var.min_capacity
  read_replica_count          = var.read_replica_count
  read_scale                  = var.read_scale
  zone_redundant              = var.zone_redundant
  license_type                = var.license_type
  ledger_enabled              = var.ledger_enabled
  tags                        = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Auditing of the database to Azure Monitor: the database's diagnostic setting below sends its records
# (SQLSecurityAuditEvents) to the workspace, one for each batch the app runs and each sign-in. With no storage endpoint
# and log_monitoring_enabled, Azure Monitor is the only target.
resource "azurerm_mssql_database_extended_auditing_policy" "example" {
  database_id            = azurerm_mssql_database.example.id
  enabled                = true
  log_monitoring_enabled = true
}

# The database writes its resource logs to the AzureDiagnostics table: none of its categories has a resource-specific
# table.
resource "azurerm_monitor_diagnostic_setting" "example" {
  name                       = var.diagnostic_setting_name
  target_resource_id         = azurerm_mssql_database.example.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}
