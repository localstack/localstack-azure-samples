locals {
  prefix                                  = lower(var.prefix)
  suffix                                  = lower(var.suffix)
  resource_group_name                     = "${var.prefix}-rg"
  log_analytics_name                      = "${local.prefix}-log-analytics-${local.suffix}"
  virtual_network_name                    = "${local.prefix}-vnet-${local.suffix}"
  nat_gateway_name                        = "${local.prefix}-nat-gateway-${local.suffix}"
  webapp_subnet_nsg_name                  = "${local.prefix}-webapp-subnet-nsg-${local.suffix}"
  pe_subnet_nsg_name                      = "${local.prefix}-pe-subnet-nsg-${local.suffix}"
  postgres_server_name                    = "${local.prefix}-pgflex-${local.suffix}"
  postgres_private_endpoint_name          = "${local.prefix}-postgres-pe-${local.suffix}"
  app_service_plan_name                   = "${local.prefix}-app-service-plan-${local.suffix}"
  web_app_name                            = "${local.prefix}-webapp-${local.suffix}"
  managed_identity_name                   = "${local.prefix}-identity-${local.suffix}"
  app_configuration_name                  = "${local.prefix}-appconfig-${local.suffix}"
  app_configuration_private_endpoint_name = "${local.prefix}-appconfig-pe-${local.suffix}"
  key_vault_name                          = "${local.prefix}-keyvault-${local.suffix}"
  key_vault_private_endpoint_name         = "${local.prefix}-keyvault-pe-${local.suffix}"

  # The PostgreSQL flexible-server emulator embeds the LS-side TCP-proxy port directly in
  # `fullyQualifiedDomainName` (e.g. "<srv>.postgres.database.localhost.localstack.cloud:4515").
  # Real Azure returns just the bare host on 5432. Split on ":" so the store always gets the
  # right host + port without any post-apply shell logic.
  pg_fqdn_parts = split(":", module.postgres_flexible_server.fqdn)
  pg_host       = local.pg_fqdn_parts[0]
  pg_port       = length(local.pg_fqdn_parts) > 1 ? local.pg_fqdn_parts[1] : var.pg_default_port

  # The five settings the Web App reads from the store: three plain key-values and two Key Vault references.
  # A Key Vault reference is a key-value with the Key Vault reference content type and the value
  # {"uri":"<versionless secret identifier>"}, so it always follows the latest version of its secret.
  app_configuration_key_values = {
    (var.pg_host_key_name)     = { value = local.pg_host }
    (var.pg_port_key_name)     = { value = local.pg_port }
    (var.pg_database_key_name) = { value = module.postgres_flexible_server.database_name }
    (var.pg_user_key_name) = {
      value        = jsonencode({ uri = module.key_vault.secret_versionless_ids[var.pg_user_secret_name] })
      content_type = var.key_vault_reference_content_type
    }
    (var.pg_password_key_name) = {
      value        = jsonencode({ uri = module.key_vault.secret_versionless_ids[var.pg_password_secret_name] })
      content_type = var.key_vault_reference_content_type
    }
  }
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
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_in_days
  tags                = var.tags
}

# VNet with two subnets:
#   * app-subnet     — delegated to Microsoft.Web/serverFarms for the Web App's regional
#                       VNet integration. Outbound through the NAT Gateway.
#   * pe-subnet      — hosts the Private Endpoints to the PostgreSQL flexible server, the App
#                       Configuration store and the Key Vault (no delegation; standard private-link subnet).
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
      private_endpoint_network_policies : var.subnet_private_endpoint_network_policies
      private_link_service_network_policies_enabled : var.subnet_private_link_service_network_policies_enabled
      delegation : var.webapp_subnet_delegation
    },
    {
      name : var.pe_subnet_name
      address_prefixes : var.pe_subnet_address_prefix
      private_endpoint_network_policies : var.subnet_private_endpoint_network_policies
      private_link_service_network_policies_enabled : var.subnet_private_link_service_network_policies_enabled
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

# -----------------------------------------------------------------------------
# User-assigned managed identity: the Web App authenticates to App Configuration and Key Vault with it.
# -----------------------------------------------------------------------------
module "managed_identity" {
  source              = "./modules/managed_identity"
  name                = local.managed_identity_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Key Vault with the Azure RBAC permission model and the two secrets the App Configuration Key Vault
# references point at. The Web App never reads the secrets directly. The module grants the deploying
# principal Key Vault Secrets Officer (when deploy.sh could resolve it) and waits for the assignment to
# propagate before it writes the secrets through the data plane.
# -----------------------------------------------------------------------------
module "key_vault" {
  source                        = "./modules/key_vault"
  name                          = local.key_vault_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = var.key_vault_sku_name
  rbac_authorization_enabled    = var.key_vault_rbac_authorization_enabled
  soft_delete_retention_days    = var.soft_delete_retention_days
  purge_protection_enabled      = var.key_vault_purge_protection_enabled
  public_network_access_enabled = var.key_vault_public_network_access_enabled
  deployer_object_id            = var.deployer_object_id
  deployer_principal_type       = var.deployer_principal_type
  deployer_role_definition_name = var.deployer_role_definition_name
  rbac_propagation_delay        = var.rbac_propagation_delay
  log_analytics_workspace_id    = module.log_analytics_workspace.id
  tags                          = var.tags

  # The application role credentials, by secret name (Key Vault secret names allow only alphanumerics and hyphens).
  secrets = {
    (var.pg_user_secret_name)     = var.pg_app_user
    (var.pg_password_secret_name) = var.pg_app_password
  }
}

# -----------------------------------------------------------------------------
# App Configuration store seeded with the five key-values. Access keys stay enabled and the Azure Resource
# Manager authentication mode stays Local (the default): the key-values are written through Azure Resource
# Manager, which in Local mode relies on the access keys. Public network access stays enabled because the
# deployment runs outside the virtual network; the Web App reaches the store through its private endpoint.
# -----------------------------------------------------------------------------
module "app_configuration" {
  source                     = "./modules/app_configuration"
  name                       = local.app_configuration_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  sku                        = var.app_configuration_sku
  local_auth_enabled         = var.app_configuration_local_auth_enabled
  public_network_access      = var.app_configuration_public_network_access
  purge_protection_enabled   = var.app_configuration_purge_protection_enabled
  soft_delete_retention_days = var.soft_delete_retention_days
  key_values                 = local.app_configuration_key_values
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
}

# -----------------------------------------------------------------------------
# Role assignments of the Web App identity: read the key-values, read the secrets behind the references.
# -----------------------------------------------------------------------------
module "app_configuration_data_reader_role_assignment" {
  source               = "./modules/role_assignment"
  scope                = module.app_configuration.id
  role_definition_name = var.app_configuration_data_reader_role_name
  principal_id         = module.managed_identity.principal_id
  principal_type       = var.managed_identity_principal_type
}

module "key_vault_secrets_user_role_assignment" {
  source               = "./modules/role_assignment"
  scope                = module.key_vault.id
  role_definition_name = var.key_vault_secrets_user_role_name
  principal_id         = module.managed_identity.principal_id
  principal_type       = var.managed_identity_principal_type
}

# -----------------------------------------------------------------------------
# Private DNS zones (linked to the virtual network) and private endpoints
# -----------------------------------------------------------------------------
module "private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = var.postgres_private_dns_zone_name
  resource_group_name = azurerm_resource_group.example.name
  tags                = var.tags
  virtual_networks_to_link = {
    (module.virtual_network.name) = {
      subscription_id     = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.example.name
    }
  }
}

module "app_configuration_private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = var.app_configuration_private_dns_zone_name
  resource_group_name = azurerm_resource_group.example.name
  tags                = var.tags
  virtual_networks_to_link = {
    (module.virtual_network.name) = {
      subscription_id     = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.example.name
    }
  }
}

module "key_vault_private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = var.key_vault_private_dns_zone_name
  resource_group_name = azurerm_resource_group.example.name
  tags                = var.tags
  virtual_networks_to_link = {
    (module.virtual_network.name) = {
      subscription_id     = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.example.name
    }
  }
}

module "postgres_flexible_server" {
  source                     = "./modules/postgres_flexible_server"
  name                       = local.postgres_server_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  administrator_login        = var.pg_admin_login
  administrator_password     = var.pg_admin_password
  postgresql_version         = var.pg_version
  sku_name                   = var.pg_sku_name
  storage_mb                 = var.pg_storage_mb
  backup_retention_days      = var.pg_backup_retention_days
  database_name              = var.pg_database_name
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
}

# Created after the server's database and firewall rule: Azure runs one operation at a time on a flexible
# server, and the private endpoint connection is one of them.
module "private_endpoint" {
  depends_on                     = [module.postgres_flexible_server]
  source                         = "./modules/private_endpoint"
  name                           = local.postgres_private_endpoint_name
  location                       = var.location
  resource_group_name            = azurerm_resource_group.example.name
  subnet_id                      = module.virtual_network.subnet_ids[var.pe_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.postgres_flexible_server.id
  is_manual_connection           = var.private_endpoint_is_manual_connection
  subresource_name               = var.postgres_private_endpoint_subresource_name
  private_dns_zone_group_name    = var.private_dns_zone_group_name
  private_dns_zone_group_ids     = [module.private_dns_zone.id]
}

module "app_configuration_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = local.app_configuration_private_endpoint_name
  location                       = var.location
  resource_group_name            = azurerm_resource_group.example.name
  subnet_id                      = module.virtual_network.subnet_ids[var.pe_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.app_configuration.id
  is_manual_connection           = var.private_endpoint_is_manual_connection
  subresource_name               = var.app_configuration_private_endpoint_subresource_name
  private_dns_zone_group_name    = var.private_dns_zone_group_name
  private_dns_zone_group_ids     = [module.app_configuration_private_dns_zone.id]
}

module "key_vault_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = local.key_vault_private_endpoint_name
  location                       = var.location
  resource_group_name            = azurerm_resource_group.example.name
  subnet_id                      = module.virtual_network.subnet_ids[var.pe_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.key_vault.id
  is_manual_connection           = var.private_endpoint_is_manual_connection
  subresource_name               = var.key_vault_private_endpoint_subresource_name
  private_dns_zone_group_name    = var.private_dns_zone_group_name
  private_dns_zone_group_ids     = [module.key_vault_private_dns_zone.id]
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

# No PG_* app setting is written. The Web App loads PG_HOST, PG_PORT, PG_DATABASE, PG_USER and PG_PASSWORD
# from the App Configuration store with the in-process provider, which also resolves the two Key Vault
# references, authenticating with the user-assigned identity that AZURE_CLIENT_ID selects.
# Endpoints__AppConfiguration is the setting the provider reads the store endpoint from (the .NET variant
# sees it as Endpoints:AppConfiguration). The post-apply step in deploy.sh only creates the PostgreSQL
# application role and seeds the schema; it writes no app setting.
module "web_app" {
  source                        = "./modules/web_app"
  name                          = local.web_app_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  service_plan_id               = module.app_service_plan.id
  https_only                    = var.https_only
  virtual_network_subnet_id     = module.virtual_network.subnet_ids[var.webapp_subnet_name]
  vnet_route_all_enabled        = var.vnet_route_all_enabled
  public_network_access_enabled = var.public_network_access_enabled
  always_on                     = var.always_on
  http2_enabled                 = var.http2_enabled
  minimum_tls_version           = var.minimum_tls_version
  dotnet_version                = var.dotnet_version
  identity_type                 = var.identity_type
  identity_ids                  = [module.managed_identity.id]
  log_analytics_workspace_id    = module.log_analytics_workspace.id
  tags                          = var.tags

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT = tostring(var.scm_do_build_during_deployment)
    ENABLE_ORYX_BUILD              = tostring(var.enable_oryx_build)
    Endpoints__AppConfiguration    = module.app_configuration.endpoint
    AZURE_CLIENT_ID                = module.managed_identity.client_id
    LOGIN_NAME                     = var.login_name
    WEBSITES_PORT                  = tostring(var.websites_port)
  }

  # The app starts only once its configuration and permissions are in place (it also retries by itself).
  depends_on = [
    module.app_configuration,
    module.app_configuration_data_reader_role_assignment,
    module.key_vault_secrets_user_role_assignment,
  ]
}
