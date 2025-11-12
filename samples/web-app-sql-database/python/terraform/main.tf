# Local Variables
locals {
  firewall_rule_name    = "AllowAllIPs"
  resource_group_name   = "${var.prefix}-rg"
  sql_server_name       = "${var.prefix}-sqlserver-${var.suffix}"
  app_service_plan_name = "${var.prefix}-app-service-plan-${var.suffix}"
  web_app_name          = "${var.prefix}-webapp-${var.suffix}"
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create a SQL server
resource "azurerm_mssql_server" "example" {
  name                                 = local.sql_server_name
  resource_group_name                  = azurerm_resource_group.example.name
  location                             = azurerm_resource_group.example.location
  administrator_login                  = var.administrator_login
  administrator_login_password         = var.administrator_login_password
  minimum_tls_version                  = var.minimum_tls_version
  public_network_access_enabled        = var.public_network_access_enabled
  outbound_network_restriction_enabled = var.outbound_network_restriction_enabled
  version                              = var.sql_version
  tags                                 = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Create a firewall rule
resource "azurerm_mssql_firewall_rule" "example" {
  name             = local.firewall_rule_name
  server_id        = azurerm_mssql_server.example.id
  start_ip_address = var.start_ip_address
  end_ip_address   = var.end_ip_address
}

# Create a database
resource "azurerm_mssql_database" "example" {
  name                        = var.sql_database_name
  server_id                   = azurerm_mssql_server.example.id
  sku_name                    = var.sku.name
  auto_pause_delay_in_minutes = var.auto_pause_delay
  collation                   = var.collation
  create_mode                 = var.create_mode
  elastic_pool_id             = var.elastic_pool_resource_id
  max_size_gb                 = var.max_size_gb
  min_capacity                = var.min_capacity != "0" ? tonumber(var.min_capacity) : null
  read_replica_count          = var.high_availability_replica_count
  read_scale                  = var.read_scale == "Enabled" ? true : false
  zone_redundant              = var.sql_database_zone_redundant
  license_type                = var.license_type
  ledger_enabled              = var.is_ledger_on
  tags                        = var.tags

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

# Create a web app
resource "azurerm_linux_web_app" "example" {
  name                          = local.web_app_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  service_plan_id               = azurerm_service_plan.example.id
  https_only                    = var.https_only
  public_network_access_enabled = var.webapp_public_network_access_enabled
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
    ENABLE_ORYX_BUILD              = "true"
    SQL_SERVER                     = azurerm_mssql_server.example.fully_qualified_domain_name
    SQL_DATABASE                   = azurerm_mssql_database.example.name
    SQL_USERNAME                   = var.sql_database_username
    SQL_PASSWORD                   = var.sql_database_password
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