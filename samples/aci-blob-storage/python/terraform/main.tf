# Local Variables
locals {
  resource_group_name  = "${var.prefix}-aci-rg"
  storage_account_name = "${var.prefix}acistorage${var.suffix}"
  key_vault_name       = "${var.prefix}acikv${var.suffix}"
  acr_name             = "${var.prefix}aciacr${var.suffix}"
  aci_group_name       = "${var.prefix}-aci-planner-${var.suffix}"
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create a storage account
resource "azurerm_storage_account" "example" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_replication_type = var.account_replication_type
  account_kind             = "StorageV2"
  account_tier             = var.account_tier
  tags                     = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Create blob container
resource "azurerm_storage_container" "example" {
  name                  = var.blob_container_name
  storage_account_id    = azurerm_storage_account.example.id
  container_access_type = "private"
}

# Create Key Vault
resource "azurerm_key_vault" "example" {
  name                       = local.key_vault_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  tags                       = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

data "azurerm_client_config" "current" {}

# Store the storage connection string in Key Vault
resource "azurerm_key_vault_secret" "storage_conn" {
  name         = "storage-conn"
  value        = "DefaultEndpointsProtocol=http;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};BlobEndpoint=${azurerm_storage_account.example.primary_blob_endpoint}"
  key_vault_id = azurerm_key_vault.example.id
}

# Create Container Registry
resource "azurerm_container_registry" "example" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  sku                 = var.acr_sku
  admin_enabled       = true
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Create Container Instance
resource "azurerm_container_group" "example" {
  name                = local.aci_group_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  os_type             = "Linux"
  restart_policy      = "Always"
  dns_name_label      = local.aci_group_name
  tags                = var.tags

  image_registry_credential {
    server   = azurerm_container_registry.example.login_server
    username = azurerm_container_registry.example.admin_username
    password = azurerm_container_registry.example.admin_password
  }

  container {
    name   = local.aci_group_name
    image  = "${azurerm_container_registry.example.login_server}/${var.image_name}:${var.image_tag}"
    cpu    = var.cpu_cores
    memory = var.memory_in_gb

    ports {
      port     = 80
      protocol = "TCP"
    }

    environment_variables = {
      BLOB_CONTAINER_NAME = var.blob_container_name
      LOGIN_NAME          = var.login_name
    }

    secure_environment_variables = {
      AZURE_STORAGE_CONNECTION_STRING = azurerm_key_vault_secret.storage_conn.value
    }
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
