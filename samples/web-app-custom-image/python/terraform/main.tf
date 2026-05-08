# Local Variables
locals {
  prefix                     = lower(var.prefix)
  suffix                     = lower(var.suffix)
  resource_group_name        = "${var.prefix}-rg"
  log_analytics_name         = "${local.prefix}-log-analytics-${local.suffix}"
  virtual_network_name       = "${local.prefix}-vnet-${local.suffix}"
  nat_gateway_name           = "${local.prefix}-nat-gateway-${local.suffix}"
  nat_gateway_ip_prefix_name = "${local.prefix}-nat-gateway-pip-prefix-${local.suffix}"
  private_endpoint_name      = "${local.prefix}-acr-pe-${local.suffix}"
  webapp_subnet_nsg_name     = "${local.prefix}-webapp-subnet-nsg-${local.suffix}"
  pe_subnet_nsg_name         = "${local.prefix}-pe-subnet-nsg-${local.suffix}"
  acr_name                   = "${local.prefix}acr${local.suffix}"
  managed_identity_name      = "${local.prefix}-identity-${local.suffix}"
  app_service_plan_name      = "${local.prefix}-app-service-plan-${local.suffix}"
  web_app_name               = "${local.prefix}-webapp-${local.suffix}"
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

# Create a container registry
module "container_registry" {
  source                     = "./modules/container_registry"
  name                       = local.acr_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = var.location
  sku                        = var.acr_sku
  admin_enabled              = var.acr_admin_enabled
  georeplication_locations   = var.acr_georeplication_locations
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
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

# Create a network security group and associate it with the webapp subnet
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

# Create a network security group and associate it with the private endpoint subnet
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

# Create a NAT gateway and associate it with the webapp subnet
module "nat_gateway" {
  source                  = "./modules/nat_gateway"
  name                    = local.nat_gateway_name
  resource_group_name     = azurerm_resource_group.example.name
  location                = var.location
  sku_name                = var.nat_gateway_sku_name
  public_ip_prefix_name   = local.nat_gateway_ip_prefix_name
  public_ip_prefix_length = 31
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
  name                = "privatelink.azurecr.io"
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
  private_connection_resource_id = module.container_registry.id
  is_manual_connection           = false
  subresource_name               = "registry"
  private_dns_zone_group_name    = "private-dns-zone-group"
  private_dns_zone_group_ids     = [module.private_dns_zone.id]
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

# Create a user-assigned managed identity
module "managed_identity" {
  source              = "./modules/managed_identity"
  name                = local.managed_identity_name
  resource_group_name = azurerm_resource_group.example.name
  location            = var.location
  acr_id              = module.container_registry.id
  tags                = var.tags
}

# Push container image to the registry
resource "null_resource" "push_image" {
  count = (var.image_name != null && var.image_name != "" && var.image_tag != null && var.image_tag != "") ? 1 : 0

  provisioner "local-exec" {
    command = "${path.root}/push_image.sh"
    environment = {
      ACR_NAME         = local.acr_name
      ACR_LOGIN_SERVER = module.container_registry.login_server
      IMAGE_NAME       = var.image_name
      IMAGE_TAG        = var.image_tag
    }
  }

  depends_on = [module.container_registry]
}

# Create Web App using module
module "web_app" {
  source                        = "./modules/web_app"
  name                          = local.web_app_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  managed_identity_id           = module.managed_identity.id
  service_plan_id               = module.app_service_plan.id
  https_only                    = var.https_only
  virtual_network_subnet_id     = module.virtual_network.subnet_ids[var.webapp_subnet_name]
  vnet_route_all_enabled        = true
  public_network_access_enabled = var.public_network_access_enabled
  always_on                     = var.always_on
  http2_enabled                 = var.http2_enabled
  minimum_tls_version           = var.minimum_tls_version
  image_name                    = var.image_name
  image_tag                     = var.image_tag
  docker_registry_url           = module.container_registry.login_server_url
  docker_registry_username      = module.container_registry.admin_username
  docker_registry_password      = module.container_registry.admin_password
  repo_url                      = var.repo_url
  log_analytics_workspace_id    = module.log_analytics_workspace.id
  tags                          = var.tags

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"
    WEBSITES_PORT                  = var.websites_port
    APP_NAME                       = "Custom Image"
    IMAGE_NAME                     = "${module.container_registry.login_server}/${var.image_name}:${var.image_tag}"
  }

  depends_on = [null_resource.push_image]
}