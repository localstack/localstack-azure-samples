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
  postgres_private_dns_zone_name          = "privatelink.postgres.database.azure.com"
  app_configuration_private_dns_zone_name = "privatelink.azconfig.io"
  key_vault_private_dns_zone_name         = "privatelink.vaultcore.azure.net"
  private_dns_zone_group_name             = "default"

  # A Key Vault reference is a key-value with this content type and the value {"uri":"<secret identifier>"}.
  key_vault_reference_content_type = "application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8"
  key_value_type                   = "Microsoft.AppConfiguration/configurationStores/keyValues@2024-06-01"

  # The PostgreSQL flexible-server emulator embeds the LS-side TCP-proxy port directly in
  # `fullyQualifiedDomainName` (e.g. "<srv>.postgres.database.localhost.localstack.cloud:4515").
  # Real Azure returns just the bare host on 5432. Split on ":" so the store always gets the
  # right host + port without any post-apply shell logic.
  pg_fqdn_parts = split(":", module.postgres_flexible_server.fqdn)
  pg_host       = local.pg_fqdn_parts[0]
  pg_port       = length(local.pg_fqdn_parts) > 1 ? local.pg_fqdn_parts[1] : "5432"
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

# -----------------------------------------------------------------------------
# User-assigned managed identity: the Web App authenticates to App Configuration and Key Vault with it.
# -----------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "web_app" {
  name                = local.managed_identity_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# App Configuration store. Access keys stay enabled and the Azure Resource Manager authentication mode
# stays Local (the default): the key-values below are written through Azure Resource Manager, which in
# Local mode relies on the access keys. Public network access stays enabled because the deployment runs
# outside the virtual network; the Web App reaches the store through its private endpoint.
# -----------------------------------------------------------------------------
resource "azurerm_app_configuration" "store" {
  name                       = local.app_configuration_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  sku                        = var.app_configuration_sku
  local_auth_enabled         = true
  public_network_access      = "Enabled"
  purge_protection_enabled   = false
  soft_delete_retention_days = var.soft_delete_retention_days
  tags                       = var.tags
}

# -----------------------------------------------------------------------------
# Key Vault with the Azure RBAC permission model (Key Vault Secrets User only works with it).
# -----------------------------------------------------------------------------
resource "azurerm_key_vault" "vault" {
  name                          = local.key_vault_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = var.key_vault_sku_name
  rbac_authorization_enabled    = true
  soft_delete_retention_days    = var.soft_delete_retention_days
  purge_protection_enabled      = false
  public_network_access_enabled = true
  tags                          = var.tags
}

# azurerm_key_vault_secret writes through the Key Vault data plane, so on Azure the deploying principal
# needs Key Vault Secrets Officer on the vault. The assignment is created here (when deploy.sh could
# resolve the principal) and the secrets wait for it to propagate.
resource "azurerm_role_assignment" "deployer_key_vault_secrets_officer" {
  count = var.deployer_object_id == "" ? 0 : 1

  scope                = azurerm_key_vault.vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.deployer_object_id
  principal_type       = var.deployer_principal_type
}

resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.deployer_key_vault_secrets_officer]
  create_duration = var.rbac_propagation_delay
}

# The application role credentials. The Web App never reads these secrets directly: it reads them through
# the App Configuration Key Vault references below.
resource "azurerm_key_vault_secret" "pg_user" {
  name         = "pg-user"
  value        = var.pg_app_user
  key_vault_id = azurerm_key_vault.vault.id
  tags         = var.tags

  depends_on = [time_sleep.rbac_propagation]
}

resource "azurerm_key_vault_secret" "pg_password" {
  name         = "pg-password"
  value        = var.pg_app_password
  key_vault_id = azurerm_key_vault.vault.id
  tags         = var.tags

  depends_on = [time_sleep.rbac_propagation]
}

# -----------------------------------------------------------------------------
# App Configuration key-values, created as ARM child resources with AzAPI (see providers.tf). The three
# plain key-values carry the PostgreSQL host, port and database name; the two Key Vault references point at
# the versionless identifiers of the secrets above, so they always follow the latest version. No label.
# -----------------------------------------------------------------------------
resource "azapi_resource" "pg_host" {
  type      = local.key_value_type
  parent_id = azurerm_app_configuration.store.id
  name      = "PG_HOST"
  body = {
    properties = {
      value = local.pg_host
    }
  }
}

resource "azapi_resource" "pg_port" {
  type      = local.key_value_type
  parent_id = azurerm_app_configuration.store.id
  name      = "PG_PORT"
  body = {
    properties = {
      value = local.pg_port
    }
  }
}

resource "azapi_resource" "pg_database" {
  type      = local.key_value_type
  parent_id = azurerm_app_configuration.store.id
  name      = "PG_DATABASE"
  body = {
    properties = {
      value = module.postgres_flexible_server.database_name
    }
  }
}

resource "azapi_resource" "pg_user_reference" {
  type      = local.key_value_type
  parent_id = azurerm_app_configuration.store.id
  name      = "PG_USER"
  body = {
    properties = {
      value       = jsonencode({ uri = azurerm_key_vault_secret.pg_user.versionless_id })
      contentType = local.key_vault_reference_content_type
    }
  }
}

resource "azapi_resource" "pg_password_reference" {
  type      = local.key_value_type
  parent_id = azurerm_app_configuration.store.id
  name      = "PG_PASSWORD"
  body = {
    properties = {
      value       = jsonencode({ uri = azurerm_key_vault_secret.pg_password.versionless_id })
      contentType = local.key_vault_reference_content_type
    }
  }
}

# -----------------------------------------------------------------------------
# Role assignments of the Web App identity: read the key-values, read the secrets behind the references.
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "app_configuration_data_reader" {
  scope                = azurerm_app_configuration.store.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = azurerm_user_assigned_identity.web_app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = azurerm_key_vault.vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.web_app.principal_id
  principal_type       = "ServicePrincipal"
}

# -----------------------------------------------------------------------------
# Private DNS zones (linked to the virtual network) and private endpoints
# -----------------------------------------------------------------------------
module "private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = local.postgres_private_dns_zone_name
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
  name                = local.app_configuration_private_dns_zone_name
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
  name                = local.key_vault_private_dns_zone_name
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
  is_manual_connection           = false
  subresource_name               = "postgresqlServer"
  private_dns_zone_group_name    = local.private_dns_zone_group_name
  private_dns_zone_group_ids     = [module.private_dns_zone.id]
}

module "app_configuration_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = local.app_configuration_private_endpoint_name
  location                       = var.location
  resource_group_name            = azurerm_resource_group.example.name
  subnet_id                      = module.virtual_network.subnet_ids[var.pe_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = azurerm_app_configuration.store.id
  is_manual_connection           = false
  subresource_name               = "configurationStores"
  private_dns_zone_group_name    = local.private_dns_zone_group_name
  private_dns_zone_group_ids     = [module.app_configuration_private_dns_zone.id]
}

module "key_vault_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = local.key_vault_private_endpoint_name
  location                       = var.location
  resource_group_name            = azurerm_resource_group.example.name
  subnet_id                      = module.virtual_network.subnet_ids[var.pe_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = azurerm_key_vault.vault.id
  is_manual_connection           = false
  subresource_name               = "vault"
  private_dns_zone_group_name    = local.private_dns_zone_group_name
  private_dns_zone_group_ids     = [module.key_vault_private_dns_zone.id]
}

# -----------------------------------------------------------------------------
# Diagnostic settings of the two new resources, sent to the Log Analytics workspace like every other resource
# -----------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "app_configuration" {
  name                       = "default"
  target_resource_id         = azurerm_app_configuration.store.id
  log_analytics_workspace_id = module.log_analytics_workspace.id

  enabled_log {
    category = "HttpRequest"
  }

  enabled_log {
    category = "Audit"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "default"
  target_resource_id         = azurerm_key_vault.vault.id
  log_analytics_workspace_id = module.log_analytics_workspace.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  enabled_metric {
    category = "AllMetrics"
  }
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
  vnet_route_all_enabled        = true
  public_network_access_enabled = var.public_network_access_enabled
  always_on                     = var.always_on
  http2_enabled                 = var.http2_enabled
  minimum_tls_version           = var.minimum_tls_version
  dotnet_version                = var.dotnet_version
  identity_type                 = "UserAssigned"
  identity_ids                  = [azurerm_user_assigned_identity.web_app.id]
  log_analytics_workspace_id    = module.log_analytics_workspace.id
  tags                          = var.tags

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"
    Endpoints__AppConfiguration    = azurerm_app_configuration.store.endpoint
    AZURE_CLIENT_ID                = azurerm_user_assigned_identity.web_app.client_id
    LOGIN_NAME                     = var.login_name
    WEBSITES_PORT                  = var.websites_port
  }

  # The app starts only once its configuration and permissions are in place (it also retries by itself).
  depends_on = [
    azurerm_role_assignment.app_configuration_data_reader,
    azurerm_role_assignment.key_vault_secrets_user,
    azapi_resource.pg_host,
    azapi_resource.pg_port,
    azapi_resource.pg_database,
    azapi_resource.pg_user_reference,
    azapi_resource.pg_password_reference,
  ]
}
