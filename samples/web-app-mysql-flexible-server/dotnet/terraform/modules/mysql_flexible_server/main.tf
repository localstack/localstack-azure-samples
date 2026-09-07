resource "azurerm_mysql_flexible_server" "this" {
  name                   = var.name
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = var.mysql_version
  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password
  sku_name               = var.sku_name
  backup_retention_days  = var.backup_retention_days
  # Public access is enabled by default (no delegated_subnet_id / private_dns_zone_id is set),
  # and a permissive firewall rule lets the deploy machine reach the server just long enough to
  # run the post-deploy mysql bootstrap. The Web App itself reaches the server through a Private
  # Endpoint (see the private_endpoint module in main.tf).
  geo_redundant_backup_enabled = false

  storage {
    size_gb = var.storage_size_gb
  }

  tags = var.tags
}

resource "azurerm_mysql_flexible_database" "this" {
  name                = var.database_name
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.this.name
  charset             = var.database_charset
  collation           = var.database_collation
}

resource "azurerm_mysql_flexible_server_firewall_rule" "allow_all" {
  name                = var.firewall_rule_name
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.this.name
  start_ip_address    = var.firewall_start_ip
  end_ip_address      = var.firewall_end_ip
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "DiagnosticsSettings"
  target_resource_id         = azurerm_mysql_flexible_server.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "MySqlSlowLogs"
  }

  enabled_log {
    category = "MySqlAuditLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
