locals {
  prefix                 = lower(var.prefix)
  suffix                 = lower(var.suffix)
  resource_group_name    = "${var.prefix}-rg"
  log_analytics_name     = "${local.prefix}-log-analytics-${local.suffix}"
  virtual_network_name   = "${local.prefix}-vnet-${local.suffix}"
  nat_gateway_name       = "${local.prefix}-nat-gateway-${local.suffix}"
  webapp_subnet_nsg_name = "${local.prefix}-webapp-subnet-nsg-${local.suffix}"
  pe_subnet_nsg_name     = "${local.prefix}-pe-subnet-nsg-${local.suffix}"
  mysql_server_name      = "${local.prefix}-mysqlflex-${local.suffix}"
  private_endpoint_name  = "${local.prefix}-mysql-pe-${local.suffix}"
  app_service_plan_name  = "${local.prefix}-app-service-plan-${local.suffix}"
  web_app_name           = "${local.prefix}-webapp-${local.suffix}"
  private_dns_zone_name  = "privatelink.mysql.database.azure.com"

  # The MySQL flexible-server emulator embeds the LS-side TCP-proxy port directly in
  # `fullyQualifiedDomainName` (e.g. "<srv>.mysql.database.localhost.localstack.cloud:4515").
  # Real Azure returns just the bare host on 3306. Split on ":" so the Web App always gets the
  # right host + port without any post-apply shell logic.
  mysql_fqdn_parts = split(":", module.mysql_flexible_server.fqdn)
  mysql_host       = local.mysql_fqdn_parts[0]
  mysql_port       = length(local.mysql_fqdn_parts) > 1 ? local.mysql_fqdn_parts[1] : "3306"
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "example" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

module "log_analytics_workspace" {
  source              = "./modules/log_analytics"
  name                = local.log_analytics_name
  location            = var.location
  resource_group_name = azurerm_resource_group.example.name
  tags                = var.tags
}

# VNet with two subnets:
#   * app-subnet     — delegated to Microsoft.Web/serverFarms for the Web App's regional
#                       VNet integration. Outbound through the NAT Gateway.
#   * pe-subnet      — hosts the Private Endpoint to the MySQL flexible server (no
#                       delegation; standard private-link subnet).
module "virtual_network" {
  source                     = "./modules/virtual_network"
  resource_group_name        = azurerm_resource_group.example.name
  location                   = var.location
  vnet_name                  = local.virtual_network_name
  address_space              = var.vnet_address_space
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags

  subnets = [
    {
      name : var.webapp_subnet_name
      address_prefixes : var.webapp_subnet_address_prefix
      private_endpoint_network_policies : "Enabled"
      private_link_service_network_policies_enabled : false
      delegation : "Microsoft.Web/serverFarms"
    },
    {
      name : var.pe_subnet_name
      address_prefixes : var.pe_subnet_address_prefix
      private_endpoint_network_policies : "Enabled"
      private_link_service_network_policies_enabled : false
      delegation : null
    }
  ]
}

module "webapp_subnet_network_security_group" {
  source                     = "./modules/network_security_group"
  name                       = local.webapp_subnet_nsg_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = var.location
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
  subnet_ids = {
    (var.webapp_subnet_name) = module.virtual_network.subnet_ids[var.webapp_subnet_name]
  }
}

module "pe_subnet_network_security_group" {
  source                     = "./modules/network_security_group"
  name                       = local.pe_subnet_nsg_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = var.location
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
  subnet_ids = {
    (var.pe_subnet_name) = module.virtual_network.subnet_ids[var.pe_subnet_name]
  }
}

module "nat_gateway" {
  source                  = "./modules/nat_gateway"
  name                    = local.nat_gateway_name
  resource_group_name     = azurerm_resource_group.example.name
  location                = var.location
  sku_name                = var.nat_gateway_sku_name
  idle_timeout_in_minutes = var.nat_gateway_idle_timeout_in_minutes
  zones                   = var.nat_gateway_zones
  subnet_ids = {
    (var.webapp_subnet_name) = module.virtual_network.subnet_ids[var.webapp_subnet_name]
  }
  tags = var.tags
}

module "private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = local.private_dns_zone_name
  resource_group_name = azurerm_resource_group.example.name
  tags                = var.tags
  virtual_networks_to_link = {
    (module.virtual_network.name) = {
      subscription_id     = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.example.name
    }
  }
}

module "mysql_flexible_server" {
  source                     = "./modules/mysql_flexible_server"
  name                       = local.mysql_server_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  administrator_login        = var.mysql_admin_login
  administrator_password     = var.mysql_admin_password
  mysql_version              = var.mysql_version
  sku_name                   = var.mysql_sku_name
  storage_size_gb            = var.mysql_storage_size_gb
  backup_retention_days      = var.mysql_backup_retention_days
  database_name              = var.mysql_database_name
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
}

module "private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = local.private_endpoint_name
  location                       = var.location
  resource_group_name            = azurerm_resource_group.example.name
  subnet_id                      = module.virtual_network.subnet_ids[var.pe_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.mysql_flexible_server.id
  is_manual_connection           = false
  subresource_name               = "mysqlServer"
  private_dns_zone_group_name    = "private-dns-zone-group"
  private_dns_zone_group_ids     = [module.private_dns_zone.id]
}

module "app_service_plan" {
  source                     = "./modules/app_service_plan"
  name                       = local.app_service_plan_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  sku_name                   = var.sku_name
  os_type                    = var.os_type
  zone_balancing_enabled     = var.zone_balancing_enabled
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
}

# Note: MYSQL_USER and MYSQL_PASSWORD are intentionally NOT set here. The post-apply step in
# deploy.sh connects to the server (via the firewall-allowed public endpoint) as the admin,
# creates the application user `testuser`, seeds the schema, and then writes `MYSQL_USER` /
# `MYSQL_PASSWORD` onto this Web App via `az webapp config appsettings set`. The server-admin
# login is never exposed to the Web App at runtime.
module "web_app" {
  source                        = "./modules/web_app"
  name                          = local.web_app_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  service_plan_id               = module.app_service_plan.id
  https_only                    = var.https_only
  virtual_network_subnet_id     = module.virtual_network.subnet_ids[var.webapp_subnet_name]
  vnet_route_all_enabled        = true
  public_network_access_enabled = var.public_network_access_enabled
  always_on                     = var.always_on
  http2_enabled                 = var.http2_enabled
  minimum_tls_version           = var.minimum_tls_version
  python_version                = var.python_version
  repo_url                      = var.repo_url
  log_analytics_workspace_id    = module.log_analytics_workspace.id
  tags                          = var.tags

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"
    MYSQL_HOST                     = local.mysql_host
    MYSQL_PORT                     = local.mysql_port
    MYSQL_DATABASE                 = module.mysql_flexible_server.database_name
    LOGIN_NAME                     = var.login_name
    WEBSITES_PORT                  = var.websites_port
  }
}
