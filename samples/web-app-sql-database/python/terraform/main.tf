# Local Variables
locals {
  firewall_rule_name        = "AllowAllIPs"
  resource_group_name       = "${var.prefix}-rg"
  sql_server_name           = "${var.prefix}-sqlserver-${var.suffix}"
  app_service_plan_name     = "${var.prefix}-app-service-plan-${var.suffix}"
  web_app_name              = "${var.prefix}-webapp-${var.suffix}"
  key_vault_name            = "${var.prefix}-kv-${var.suffix}"
  sql_identity_name         = "${var.prefix}-tde-identity-${var.suffix}"
  web_app_identity_name     = "${var.prefix}-webapp-identity-${var.suffix}"
  tde_key_name              = "${var.prefix}-tde-key-${var.suffix}"
  log_analytics_name        = "${var.prefix}-log-analytics-${var.suffix}"
  application_insights_name = "${var.prefix}-insights-${var.suffix}"
}

# Retrieve the current Azure client configuration
data "azurerm_client_config" "current" {}

# Create a resource group
resource "azurerm_resource_group" "example" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create the Log Analytics workspace that receives the telemetry of Application Insights and the resource logs and
# platform metrics the diagnostic settings send
module "log_analytics_workspace" {
  source              = "./modules/log_analytics"
  name                = local.log_analytics_name
  location            = var.location
  resource_group_name = azurerm_resource_group.example.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_in_days
  tags                = var.tags
}

# Create the workspace-based Application Insights component that collects the web app's requests, dependencies, logs,
# exceptions, custom events and custom metrics
module "application_insights" {
  source              = "./modules/application_insights"
  name                = local.application_insights_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  workspace_id        = module.log_analytics_workspace.id
  tags                = var.tags
}

# Create the user-assigned managed identity the SQL server uses to reach the TDE protector key
module "sql_server_identity" {
  source              = "./modules/managed_identity"
  name                = local.sql_identity_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  tags                = var.tags
}

# Create the user-assigned managed identity the web app reads the connection string and the certificate with
module "web_app_identity" {
  source              = "./modules/managed_identity"
  name                = local.web_app_identity_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  tags                = var.tags
}

# Create the SQL server, its firewall rule and the database, whose auditing and diagnostic setting send to the workspace
module "sql_server" {
  source                               = "./modules/mssql_server"
  name                                 = local.sql_server_name
  resource_group_name                  = azurerm_resource_group.example.name
  location                             = azurerm_resource_group.example.location
  administrator_login                  = var.administrator_login
  administrator_login_password         = var.administrator_login_password
  minimum_tls_version                  = var.minimum_tls_version
  public_network_access_enabled        = var.public_network_access_enabled
  outbound_network_restriction_enabled = var.outbound_network_restriction_enabled
  sql_version                          = var.sql_version
  managed_identity_id                  = module.sql_server_identity.id
  firewall_rule_name                   = local.firewall_rule_name
  start_ip_address                     = var.start_ip_address
  end_ip_address                       = var.end_ip_address
  database_name                        = var.sql_database_name
  sku_name                             = var.sku.name
  auto_pause_delay                     = var.auto_pause_delay
  collation                            = var.collation
  create_mode                          = var.create_mode
  elastic_pool_id                      = var.elastic_pool_resource_id
  max_size_gb                          = var.max_size_gb
  min_capacity                         = var.min_capacity != "0" ? tonumber(var.min_capacity) : null
  read_replica_count                   = var.high_availability_replica_count
  read_scale                           = var.read_scale == "Enabled" ? true : false
  zone_redundant                       = var.sql_database_zone_redundant
  license_type                         = var.license_type
  ledger_enabled                       = var.is_ledger_on
  log_analytics_workspace_id           = module.log_analytics_workspace.id
  tags                                 = var.tags
}

# Create the Key Vault, with the Azure RBAC permission model, and in it the TDE protector key, the SQL connection string
# secret and the certificate the web app serves HTTPS with. The module grants the deploying principal the Key Vault
# Crypto, Secrets and Certificates Officer roles (when deploy.sh could resolve it) and waits for them to propagate
# before it writes the three objects through the data plane.
module "key_vault" {
  source                         = "./modules/key_vault"
  name                           = local.key_vault_name
  resource_group_name            = azurerm_resource_group.example.name
  location                       = azurerm_resource_group.example.location
  tenant_id                      = data.azurerm_client_config.current.tenant_id
  rbac_authorization_enabled     = var.key_vault_rbac_authorization_enabled
  deployer_object_id             = var.deployer_object_id
  deployer_principal_type        = var.deployer_principal_type
  deployer_role_definition_names = var.deployer_role_definition_names
  rbac_propagation_delay         = var.rbac_propagation_delay
  tde_key_name                   = local.tde_key_name
  secret_name                    = var.secret_name
  sql_server_fqdn                = module.sql_server.fully_qualified_domain_name
  sql_database_name              = module.sql_server.database_name
  sql_database_username          = var.sql_database_username
  sql_database_password          = var.sql_database_password
  cert_name                      = var.cert_name
  cert_subject                   = var.cert_subject
  log_analytics_workspace_id     = module.log_analytics_workspace.id
  tags                           = var.tags
}

# Role assignments on the Key Vault. The web app reads the connection string and the private key of its certificate as
# secrets, and the certificate itself, with its user-assigned managed identity. The SQL server wraps and unwraps its
# database encryption keys with the TDE protector key through its own user-assigned managed identity: Azure SQL checks
# that access before it accepts the key, so that assignment waits for the role to propagate.
module "web_app_key_vault_secrets_user_role_assignment" {
  source               = "./modules/role_assignment"
  scope                = module.key_vault.id
  role_definition_name = var.key_vault_secrets_user_role_name
  principal_id         = module.web_app_identity.principal_id
  principal_type       = var.managed_identity_principal_type
}

module "web_app_key_vault_certificate_user_role_assignment" {
  source               = "./modules/role_assignment"
  scope                = module.key_vault.id
  role_definition_name = var.key_vault_certificate_user_role_name
  principal_id         = module.web_app_identity.principal_id
  principal_type       = var.managed_identity_principal_type
}

module "sql_server_key_vault_crypto_service_encryption_user_role_assignment" {
  source               = "./modules/role_assignment"
  scope                = module.key_vault.id
  role_definition_name = var.key_vault_crypto_service_encryption_user_role_name
  principal_id         = module.sql_server_identity.principal_id
  principal_type       = var.managed_identity_principal_type
  propagation_delay    = var.rbac_propagation_delay
}

# Make the Key Vault key the TDE protector of the SQL server, once the server's identity can use it
module "transparent_data_encryption" {
  source           = "./modules/transparent_data_encryption"
  server_id        = module.sql_server.id
  key_vault_key_id = module.key_vault.tde_key_id

  depends_on = [module.sql_server_key_vault_crypto_service_encryption_user_role_assignment]
}

# Create a service plan
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

# Create a web app with the user-assigned managed identity. The app reads the connection string from the vault itself:
# its settings carry the names of the vault, of the secret and of the certificate, and AZURE_CLIENT_ID selects the
# identity it authenticates with.
module "web_app" {
  source                        = "./modules/web_app"
  name                          = local.web_app_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  service_plan_id               = module.app_service_plan.id
  https_only                    = var.https_only
  public_network_access_enabled = var.webapp_public_network_access_enabled
  client_affinity_enabled       = false
  identity_type                 = var.web_app_identity_type
  identity_ids                  = [module.web_app_identity.id]
  always_on                     = var.always_on
  http2_enabled                 = var.http2_enabled
  minimum_tls_version           = var.minimum_tls_version
  python_version                = var.python_version
  log_analytics_workspace_id    = module.log_analytics_workspace.id
  tags                          = var.tags

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT        = "true"
    ENABLE_ORYX_BUILD                     = "true"
    KEY_VAULT_NAME                        = module.key_vault.name
    SECRET_NAME                           = module.key_vault.secret_name
    KEYVAULT_URI                          = module.key_vault.vault_uri
    CERT_NAME                             = module.key_vault.certificate_name
    AZURE_CLIENT_ID                       = module.web_app_identity.client_id
    LOGIN_NAME                            = var.login_name
    APPLICATIONINSIGHTS_CONNECTION_STRING = module.application_insights.connection_string
  }
}
