locals {
  resource_group_name  = "${var.prefix}-rg"
  storage_account_name = "${var.prefix}msastorage${var.suffix}"
  key_vault_name       = "${var.prefix}-msa-kv-${var.suffix}"
  postgres_server_name = "${var.prefix}-msa-pgflex-${var.suffix}"
  servicebus_namespace = "${var.prefix}-msa-sb-ns-${var.suffix}"
  log_analytics_name   = "${var.prefix}-msa-log-analytics-${var.suffix}"
  app_service_plan     = "${var.prefix}-msa-app-service-plan-${var.suffix}"
  web_app_name         = "${var.prefix}-msa-webapp-${var.suffix}"
  function_app_name    = "${var.prefix}-msa-functionapp-${var.suffix}"
  identity_name        = "${var.prefix}-msa-identity-${var.suffix}"
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "example" {
  name     = local.resource_group_name
  location = var.location
}

# ---------------------------------------------------------------------------
# Identity - one user-assigned identity shared by the web app and the worker;
# every storage and Key Vault data-plane access is credential-free through it.
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "example" {
  name                = local.identity_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
}

# ---------------------------------------------------------------------------
# Storage - table (links store), queue (QR render jobs), blob (QR images)
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "example" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_table" "links" {
  name                 = "links"
  storage_account_name = azurerm_storage_account.example.name
}

resource "azurerm_storage_queue" "qrjobs" {
  name                 = "qrjobs"
  storage_account_name = azurerm_storage_account.example.name
}

resource "azurerm_storage_container" "qrcodes" {
  name                  = "qrcodes"
  storage_account_name  = azurerm_storage_account.example.name
  container_access_type = "blob"
}

resource "azurerm_role_assignment" "table_contributor" {
  scope                = azurerm_storage_account.example.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.example.principal_id
}

resource "azurerm_role_assignment" "queue_contributor" {
  scope                = azurerm_storage_account.example.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.example.principal_id
}

resource "azurerm_role_assignment" "blob_contributor" {
  scope                = azurerm_storage_account.example.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.example.principal_id
}

# ---------------------------------------------------------------------------
# Key Vault - holds the link-signing key and the PostgreSQL connection string
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "example" {
  name                       = local.key_vault_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
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

resource "azurerm_key_vault_secret" "sign_key" {
  name         = "link-sign-key"
  value        = random_password.sign_key.result
  key_vault_id = azurerm_key_vault.example.id
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.example.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.example.principal_id
}

# ---------------------------------------------------------------------------
# PostgreSQL flexible server - click-event log written on every redirect
# ---------------------------------------------------------------------------
resource "azurerm_postgresql_flexible_server" "example" {
  name                   = local.postgres_server_name
  resource_group_name    = azurerm_resource_group.example.name
  location               = azurerm_resource_group.example.location
  version                = var.postgres_version
  administrator_login    = "linkletadmin"
  administrator_password = random_password.postgres.result
  sku_name               = var.postgres_sku_name
  storage_mb             = var.postgres_storage_mb

  lifecycle {
    # Real Azure assigns an availability zone at create time; the provider
    # refuses to change it afterwards, so keep whatever was assigned.
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "clicks" {
  name      = "clicks"
  server_id = azurerm_postgresql_flexible_server.example.id
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_all" {
  name             = "AllowAllIPs"
  server_id        = azurerm_postgresql_flexible_server.example.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

# The PostgreSQL flexible-server emulator embeds the LS-side TCP-proxy port directly in
# `fullyQualifiedDomainName` (e.g. "<srv>.postgres.database.localhost.localstack.cloud:4515").
# Real Azure returns just the bare host on 5432. Split on ":" so the app always gets the
# right host + port without any post-apply shell logic.
locals {
  pg_fqdn_parts = split(":", azurerm_postgresql_flexible_server.example.fqdn)
  pg_host       = local.pg_fqdn_parts[0]
  pg_port       = length(local.pg_fqdn_parts) > 1 ? local.pg_fqdn_parts[1] : "5432"
}

resource "azurerm_key_vault_secret" "pg_conn" {
  name         = "pg-conn"
  value        = "host=${local.pg_host} port=${local.pg_port} dbname=${azurerm_postgresql_flexible_server_database.clicks.name} user=linkletadmin password=${random_password.postgres.result}"
  key_vault_id = azurerm_key_vault.example.id
}

# ---------------------------------------------------------------------------
# Service Bus - link-created events consumed by the abuse-scan worker
# ---------------------------------------------------------------------------
resource "azurerm_servicebus_namespace" "example" {
  name                = local.servicebus_namespace
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  sku                 = var.servicebus_sku
}

resource "azurerm_servicebus_queue" "link_events" {
  name         = "link-events"
  namespace_id = azurerm_servicebus_namespace.example.id
}

resource "azurerm_role_assignment" "sb_sender" {
  scope                = azurerm_servicebus_namespace.example.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.example.principal_id
}

resource "azurerm_role_assignment" "sb_receiver" {
  scope                = azurerm_servicebus_namespace.example.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.example.principal_id
}

# ---------------------------------------------------------------------------
# Observability - Log Analytics workspace (diagnostic settings are attached by
# deploy.sh, mirroring the sibling samples)
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "example" {
  name                = local.log_analytics_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# ---------------------------------------------------------------------------
# Compute - one Linux plan hosting both the web app and the worker
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "example" {
  name                = local.app_service_plan
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
}

resource "azurerm_linux_web_app" "example" {
  name                = local.web_app_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  service_plan_id     = azurerm_service_plan.example.id

  site_config {
    application_stack {
      python_version = "3.13"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.example.id]
  }

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    AZURE_CLIENT_ID                = azurerm_user_assigned_identity.example.client_id
    AZURE_TABLES_ENDPOINT          = azurerm_storage_account.example.primary_table_endpoint
    LINKS_TABLE                    = azurerm_storage_table.links.name
    KEYVAULT_URL                   = azurerm_key_vault.example.vault_uri
    QUEUE_ENDPOINT                 = azurerm_storage_account.example.primary_queue_endpoint
    QR_JOBS_QUEUE                  = azurerm_storage_queue.qrjobs.name
    BLOB_ENDPOINT                  = azurerm_storage_account.example.primary_blob_endpoint
    QR_CONTAINER                   = azurerm_storage_container.qrcodes.name
    # The python Service Bus SDK enforces TLS verification, and the emulator's
    # certificate does not cover *.servicebus.windows.net - so the app uses the
    # namespace connection string, whose endpoint is certificate-valid on both
    # the emulator and real Azure.
    SB_CONN        = azurerm_servicebus_namespace.example.default_primary_connection_string
    SB_QUEUE       = azurerm_servicebus_queue.link_events.name
    PG_SECRET_NAME = azurerm_key_vault_secret.pg_conn.name
    INTERNAL_TOKEN = random_password.internal_token.result
  }
}

resource "azurerm_linux_function_app" "example" {
  name                        = local.function_app_name
  resource_group_name         = azurerm_resource_group.example.name
  location                    = azurerm_resource_group.example.location
  service_plan_id             = azurerm_service_plan.example.id
  storage_account_name        = azurerm_storage_account.example.name
  storage_account_access_key  = azurerm_storage_account.example.primary_access_key
  functions_extension_version = "~4"

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.example.id]
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME       = "python"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"
    AZURE_CLIENT_ID                = azurerm_user_assigned_identity.example.client_id
    # Identity-based Service Bus trigger binding (same pattern as the
    # function-app-service-bus sample): no connection string, MI + FQNS.
    ServiceBusConnection__fullyQualifiedNamespace = "${azurerm_servicebus_namespace.example.name}.servicebus.windows.net"
    ServiceBusConnection__clientId                = azurerm_user_assigned_identity.example.client_id
    ServiceBusConnection__credential              = "managedidentity"
    # Dedicated queue-trigger connection with explicit endpoints: the .NET
    # Queues extension cannot parse a connection string whose EndpointSuffix
    # carries the emulator's port.
    QrStorage      = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};BlobEndpoint=${azurerm_storage_account.example.primary_blob_endpoint};QueueEndpoint=${azurerm_storage_account.example.primary_queue_endpoint};TableEndpoint=${azurerm_storage_account.example.primary_table_endpoint}"
    WEB_BASE_URL   = "http://${azurerm_linux_web_app.example.default_hostname}"
    INTERNAL_TOKEN = random_password.internal_token.result
  }
}
