locals {
  resource_group_name       = "${var.prefix}-rg"
  storage_account_name      = "${var.prefix}urlshortstorage${var.suffix}"
  key_vault_name            = "${var.prefix}-urlshort-kv-${var.suffix}"
  postgres_server_name      = "${var.prefix}-urlshort-pgflex-${var.suffix}"
  servicebus_namespace      = "${var.prefix}-urlshort-sb-ns-${var.suffix}"
  log_analytics_name        = "${var.prefix}-urlshort-log-analytics-${var.suffix}"
  application_insights_name = "${var.prefix}-urlshort-insights-${var.suffix}"
  app_service_plan          = "${var.prefix}-urlshort-app-service-plan-${var.suffix}"
  web_app_name              = "${var.prefix}-urlshort-webapp-${var.suffix}"
  function_app_name         = "${var.prefix}-urlshort-functionapp-${var.suffix}"
  identity_name             = "${var.prefix}-urlshort-identity-${var.suffix}"
  links_table_name          = "links"
  qr_jobs_queue_name        = "qrjobs"
  qr_container_name         = "qrcodes"
  servicebus_queue_name     = "link-events"
  postgres_admin_login      = "linkletadmin"

  # The PostgreSQL flexible-server emulator embeds the LS-side TCP-proxy port directly in
  # `fullyQualifiedDomainName` (e.g. "<srv>.postgres.database.localhost.localstack.cloud:4515").
  # Real Azure returns just the bare host on 5432. Split on ":" so the app always gets the
  # right host + port without any post-apply shell logic.
  pg_fqdn_parts = split(":", module.postgres_flexible_server.fqdn)
  pg_host       = local.pg_fqdn_parts[0]
  pg_port       = length(local.pg_fqdn_parts) > 1 ? local.pg_fqdn_parts[1] : "5432"

  # Explicit endpoints rather than an EndpointSuffix: the Functions host parses AzureWebJobsStorage with the strict .NET
  # storage clients, which cannot parse the EndpointSuffix-with-port string the provider would compose on the emulator,
  # and the .NET Queues extension of the QR trigger can't either.
  storage_connection_string = "DefaultEndpointsProtocol=https;AccountName=${module.storage_account.name};AccountKey=${module.storage_account.primary_access_key};BlobEndpoint=${module.storage_account.primary_blob_endpoint};QueueEndpoint=${module.storage_account.primary_queue_endpoint};TableEndpoint=${module.storage_account.primary_table_endpoint}"
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "random_password" "sign_key" {
  length  = 32
  special = false
}

resource "random_password" "postgres" {
  length  = 20
  special = false
}

resource "random_password" "internal_token" {
  length  = 24
  special = false
}

# ---------------------------------------------------------------------------
# Observability - the Log Analytics workspace and Application Insights
# ---------------------------------------------------------------------------
module "log_analytics_workspace" {
  source              = "./modules/log_analytics"
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_in_days
  tags                = var.tags
}

module "application_insights" {
  source              = "./modules/application_insights"
  name                = local.application_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = module.log_analytics_workspace.id
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Identity - one user-assigned identity shared by the web app and the worker;
# every storage and Key Vault data-plane access is credential-free through it.
# ---------------------------------------------------------------------------
module "managed_identity" {
  source              = "./modules/managed_identity"
  name                = local.identity_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Storage - table (links store), queue (QR render jobs), blob (QR images)
# ---------------------------------------------------------------------------
module "storage_account" {
  source                          = "./modules/storage_account"
  name                            = local.storage_account_name
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  allow_nested_items_to_be_public = var.storage_allow_nested_items_to_be_public
  table_names                     = [local.links_table_name]
  queue_names                     = [local.qr_jobs_queue_name]
  container_names                 = [local.qr_container_name]
  container_access_type           = "blob"
  diagnostic_services             = ["blob", "queue", "table"]
  log_analytics_workspace_id      = module.log_analytics_workspace.id
  tags                            = var.tags
}

module "storage_role_assignments" {
  source               = "./modules/role_assignment"
  for_each             = toset(["Storage Table Data Contributor", "Storage Queue Data Contributor", "Storage Blob Data Contributor"])
  scope                = module.storage_account.id
  role_definition_name = each.value
  principal_id         = module.managed_identity.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------------------------------------------------------------------------
# PostgreSQL flexible server - click-event log written on every redirect
# ---------------------------------------------------------------------------
module "postgres_flexible_server" {
  source                     = "./modules/postgres_flexible_server"
  name                       = local.postgres_server_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  administrator_login        = local.postgres_admin_login
  administrator_password     = random_password.postgres.result
  postgresql_version         = var.postgres_version
  sku_name                   = var.postgres_sku_name
  storage_mb                 = var.postgres_storage_mb
  database_name              = "clicks"
  firewall_rule_name         = "AllowAllIPs"
  firewall_start_ip          = "0.0.0.0"
  firewall_end_ip            = "255.255.255.255"
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
}

# ---------------------------------------------------------------------------
# Key Vault - holds the link-signing key and the PostgreSQL connection string
# ---------------------------------------------------------------------------
module "key_vault" {
  source                     = "./modules/key_vault"
  name                       = local.key_vault_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  rbac_authorization_enabled = true
  deployer_object_id         = var.deployer_object_id
  deployer_principal_type    = var.deployer_principal_type
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags

  secrets = {
    "link-sign-key" = random_password.sign_key.result
    "pg-conn"       = "host=${local.pg_host} port=${local.pg_port} dbname=${module.postgres_flexible_server.database_name} user=${local.postgres_admin_login} password=${random_password.postgres.result}"
  }
}

module "key_vault_secrets_user_role_assignment" {
  source               = "./modules/role_assignment"
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.managed_identity.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------------------------------------------------------------------------
# Service Bus - link-created events consumed by the abuse-scan worker
# ---------------------------------------------------------------------------
module "service_bus" {
  source                     = "./modules/service_bus"
  name                       = local.servicebus_namespace
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  sku                        = var.servicebus_sku
  queue_names                = [local.servicebus_queue_name]
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
}

module "service_bus_role_assignments" {
  source               = "./modules/role_assignment"
  for_each             = toset(["Azure Service Bus Data Sender", "Azure Service Bus Data Receiver"])
  scope                = module.service_bus.id
  role_definition_name = each.value
  principal_id         = module.managed_identity.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------------------------------------------------------------------------
# Compute - one Linux plan hosting both the web app and the worker
# ---------------------------------------------------------------------------
module "app_service_plan" {
  source                     = "./modules/app_service_plan"
  name                       = local.app_service_plan
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  sku_name                   = var.app_service_plan_sku
  os_type                    = "Linux"
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
}

module "web_app" {
  source                     = "./modules/web_app"
  name                       = local.web_app_name
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = module.app_service_plan.id
  python_version             = "3.13"
  identity_type              = "UserAssigned"
  identity_ids               = [module.managed_identity.id]
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    AZURE_CLIENT_ID                = module.managed_identity.client_id
    AZURE_TABLES_ENDPOINT          = module.storage_account.primary_table_endpoint
    LINKS_TABLE                    = local.links_table_name
    KEYVAULT_URL                   = module.key_vault.vault_uri
    QUEUE_ENDPOINT                 = module.storage_account.primary_queue_endpoint
    QR_JOBS_QUEUE                  = local.qr_jobs_queue_name
    BLOB_ENDPOINT                  = module.storage_account.primary_blob_endpoint
    QR_CONTAINER                   = local.qr_container_name
    # The python Service Bus SDK enforces TLS verification, and the emulator's
    # certificate does not cover *.servicebus.windows.net - so the app uses the
    # namespace connection string, whose endpoint is certificate-valid on both
    # the emulator and real Azure.
    SB_CONN                               = module.service_bus.namespace_connection_string
    SB_QUEUE                              = local.servicebus_queue_name
    PG_SECRET_NAME                        = "pg-conn"
    INTERNAL_TOKEN                        = random_password.internal_token.result
    APPLICATIONINSIGHTS_CONNECTION_STRING = module.application_insights.connection_string
  }

  # The secrets the app reads at start must exist first
  depends_on = [module.key_vault]
}

module "function_app" {
  source                                 = "./modules/function_app"
  name                                   = local.function_app_name
  resource_group_name                    = azurerm_resource_group.main.name
  location                               = azurerm_resource_group.main.location
  service_plan_id                        = module.app_service_plan.id
  storage_account_name                   = module.storage_account.name
  storage_account_access_key             = module.storage_account.primary_access_key
  always_on                              = true
  application_insights_connection_string = module.application_insights.connection_string
  python_version                         = "3.11"
  identity_type                          = "UserAssigned"
  identity_ids                           = [module.managed_identity.id]
  log_analytics_workspace_id             = module.log_analytics_workspace.id
  tags                                   = var.tags

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME       = "python"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"
    AzureWebJobsStorage            = local.storage_connection_string
    AZURE_CLIENT_ID                = module.managed_identity.client_id
    # Identity-based Service Bus trigger binding (same pattern as the
    # function-app-service-bus sample): no connection string, MI + FQNS.
    ServiceBusConnection__fullyQualifiedNamespace = "${module.service_bus.name}.servicebus.windows.net"
    ServiceBusConnection__clientId                = module.managed_identity.client_id
    ServiceBusConnection__credential              = "managedidentity"
    # Dedicated queue-trigger connection with explicit endpoints
    QrStorage      = local.storage_connection_string
    WEB_BASE_URL   = "http://${module.web_app.default_hostname}"
    INTERNAL_TOKEN = random_password.internal_token.result
    # The Python worker sends its own telemetry through OpenTelemetry, which host.json turns on, instead of the host
    # forwarding its log records, and only the records of the functions' logger
    PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY = "true"
    PYTHON_APPLICATIONINSIGHTS_LOGGER_NAME      = "function_app"
  }
}
