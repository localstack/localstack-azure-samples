# Local Variables
locals {
  prefix                      = lower(var.prefix)
  suffix                      = lower(var.suffix)
  resource_group_name         = "${var.prefix}-rg"
  log_analytics_name          = "${local.prefix}-log-analytics-${local.suffix}"
  virtual_network_name        = "${local.prefix}-vnet-${local.suffix}"
  nat_gateway_name            = "${local.prefix}-nat-gateway-${local.suffix}"
  private_endpoint_name       = "${local.prefix}-mongodb-pe-${local.suffix}"
  network_security_group_name = "${local.prefix}-default-nsg-${local.suffix}"
  cosmosdb_account_name       = "${local.prefix}-mongodb-${local.suffix}"
  app_service_plan_name       = "${local.prefix}-app-service-plan-${local.suffix}"
  web_app_name                = "${local.prefix}-webapp-${local.suffix}"
}

# Data Sources
data "azurerm_client_config" "current" {
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create a log analytics workspace
module "log_analytics_workspace" {
  source              = "./modules/log_analytics"
  name                = local.log_analytics_name
  location            = var.location
  resource_group_name = azurerm_resource_group.example.name
  tags                = var.tags
}

# Create a virtual network with subnets
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

# Create a network security group and associate it with the default subnet
module "network_security_group" {
  source                     = "./modules/network_security_group"
  name                       = local.network_security_group_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = var.location
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
  subnet_ids = {
    (var.webapp_subnet_name) = module.virtual_network.subnet_ids[var.webapp_subnet_name]
  }

}

# Create a NAT gateway and associate it with the default subnet
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

# Create a private DNS zone for the CosmosDB MongoDB account and link it to the virtual network
module "private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = "privatelink.mongo.cosmos.azure.com"
  resource_group_name = azurerm_resource_group.example.name
  tags                = var.tags
  virtual_networks_to_link = {
    (module.virtual_network.name) = {
      subscription_id     = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.example.name
    }
  }
}

# Create a private endpoint for the CosmosDB MongoDB account in the pe_subnet subnet
module "private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = local.private_endpoint_name
  location                       = var.location
  resource_group_name            = azurerm_resource_group.example.name
  subnet_id                      = module.virtual_network.subnet_ids[var.pe_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.cosmosdb_mongodb.id
  is_manual_connection           = false
  subresource_name               = "mongodb"
  private_dns_zone_group_name    = "private-dns-zone-group"
  private_dns_zone_group_ids     = [module.private_dns_zone.id]
}

# Create CosmosDB MongoDB resources using module
module "cosmosdb_mongodb" {
  source                     = "./modules/cosmosdb_mongodb"
  name                       = local.cosmosdb_account_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  mongo_server_version       = var.mongodb_server_version
  consistency_level          = var.consistency_level
  primary_region             = var.primary_region
  secondary_region           = var.secondary_region
  database_name              = var.cosmosdb_database_name
  database_throughput        = var.database_throughput
  collection_name            = var.cosmosdb_collection_name
  index_keys                 = var.mongodb_index_keys
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
}

# Create App Service Plan using module
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

# Create Web App using module
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
    COSMOSDB_CONNECTION_STRING     = module.cosmosdb_mongodb.primary_mongodb_connection_string
    COSMOSDB_DATABASE_NAME         = module.cosmosdb_mongodb.database_name
    COSMOSDB_COLLECTION_NAME       = var.cosmosdb_collection_name
    LOGIN_NAME                     = var.login_name
    WEBSITE_PORT                   = var.website_port
  }
}