###############################################################################
# PostgreSQL Flexible Server Sample - Terraform Configuration
#
# Creates a PostgreSQL Flexible Server with databases and firewall rules
# on LocalStack for Azure.
#
# Provider configuration is in providers.tf
# Variable definitions are in variables.tf
# Output definitions are in outputs.tf
###############################################################################

resource "random_uuid" "uuid" {}

locals {
  server_name = "pgflex-${substr(random_uuid.uuid.result, 0, 6)}"
}

###############################################################################
# Resource Group
###############################################################################

resource "azurerm_resource_group" "rg" {
  name     = "rg-pgflex-${random_uuid.uuid.result}"
  location = var.location

  tags = var.tags
}

###############################################################################
# PostgreSQL Flexible Server
###############################################################################

resource "azurerm_postgresql_flexible_server" "pg" {
  name                          = local.server_name
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  version                       = var.postgresql_version
  administrator_login           = var.administrator_login
  administrator_password        = var.administrator_password
  storage_mb                    = var.storage_mb
  sku_name                      = var.sku_name
  zone                          = "1"
  public_network_access_enabled = var.public_network_access_enabled

  # Backup configuration
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  tags = var.tags
}

###############################################################################
# Databases
###############################################################################

resource "azurerm_postgresql_flexible_server_database" "primary_db" {
  name      = var.primary_database_name
  server_id = azurerm_postgresql_flexible_server.pg.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Second database to test multiple database support
resource "azurerm_postgresql_flexible_server_database" "secondary_db" {
  name      = var.secondary_database_name
  server_id = azurerm_postgresql_flexible_server.pg.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

###############################################################################
# Firewall Rules
###############################################################################

# Allow all access (development/testing)
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_all" {
  name             = "allow-all"
  server_id        = azurerm_postgresql_flexible_server.pg.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

# Simulated corporate network access
resource "azurerm_postgresql_flexible_server_firewall_rule" "corporate" {
  name             = "corporate-network"
  server_id        = azurerm_postgresql_flexible_server.pg.id
  start_ip_address = "10.0.0.1"
  end_ip_address   = "10.0.255.255"
}

# Simulated VPN access
resource "azurerm_postgresql_flexible_server_firewall_rule" "vpn" {
  name             = "vpn-access"
  server_id        = azurerm_postgresql_flexible_server.pg.id
  start_ip_address = "192.168.100.1"
  end_ip_address   = "192.168.100.254"
}
