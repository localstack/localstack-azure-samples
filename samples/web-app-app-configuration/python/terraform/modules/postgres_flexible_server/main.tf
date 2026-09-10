resource "azurerm_postgresql_flexible_server" "this" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = var.postgresql_version
  administrator_login          = var.administrator_login
  administrator_password       = var.administrator_password
  sku_name                     = var.sku_name
  storage_mb                   = var.storage_mb
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = false
  # Public access is enabled and a permissive firewall rule lets the deploy machine reach the
  # server just long enough to run the post-deploy psql bootstrap. The Web App itself reaches
  # the server through a Private Endpoint (see the private_endpoint module in main.tf).
  public_network_access_enabled = true

  tags = var.tags

  lifecycle {
    # Azure picks the availability zone of a zone-redundancy-disabled server; the provider refuses to
    # "change" it back to unset on the next plan, so the assigned zone is left alone.
    ignore_changes = [zone, high_availability[0].standby_availability_zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = var.database_charset
  collation = var.database_collation
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_all" {
  name             = var.firewall_rule_name
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = var.firewall_start_ip
  end_ip_address   = var.firewall_end_ip

  # Azure runs one operation at a time on a flexible server ("ServerIsBusy" otherwise), so the firewall
  # rule waits for the database instead of being created in parallel with it.
  depends_on = [azurerm_postgresql_flexible_server_database.this]
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  name                       = "DiagnosticsSettings"
  target_resource_id         = azurerm_postgresql_flexible_server.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "PostgreSQLLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
