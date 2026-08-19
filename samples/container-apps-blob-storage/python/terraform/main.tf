# Local Variables
locals {
  resource_group_name  = "${var.prefix}-aca-rg"
  storage_account_name = "${var.prefix}acastorage${var.suffix}"
  acr_name             = "${var.prefix}acaacr${var.suffix}"
  environment_name     = "${var.prefix}-aca-env-${var.suffix}"
  app_name             = "${var.prefix}-aca-guestbook-${var.suffix}"

  # Secret NAMES referenced from more than one block, kept in one place so the
  # references never drift apart.
  storage_conn_secret_name      = "storage-conn"
  registry_password_secret_name = "registry-password"
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags

  lifecycle {
    # deploy.sh pre-creates this resource group with `az group create` (untagged) and
    # imports it into the Terraform state. Ignoring tag drift avoids an in-place
    # resource-group update on the next apply, which azurerm >= 4.x issues as a PATCH
    # request that the LocalStack Azure emulator does not implement yet.
    ignore_changes = [tags]
  }
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

# Reference the pre-created ACR (created by deploy.sh before terraform apply)
data "azurerm_container_registry" "example" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.example.name
}

# Create the Container Apps managed environment
resource "azurerm_container_app_environment" "example" {
  name                = local.environment_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Create the container app
resource "azurerm_container_app" "example" {
  name                         = local.app_name
  container_app_environment_id = azurerm_container_app_environment.example.id
  resource_group_name          = azurerm_resource_group.example.name
  revision_mode                = "Multiple"
  tags                         = var.tags

  # The storage connection string is a Container Apps secret, referenced from
  # the container below via secret_name.
  secret {
    name  = local.storage_conn_secret_name
    value = "DefaultEndpointsProtocol=http;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};BlobEndpoint=${azurerm_storage_account.example.primary_blob_endpoint}"
  }

  secret {
    name  = local.registry_password_secret_name
    value = data.azurerm_container_registry.example.admin_password
  }

  registry {
    server               = data.azurerm_container_registry.example.login_server
    username             = data.azurerm_container_registry.example.admin_username
    password_secret_name = local.registry_password_secret_name
  }

  ingress {
    external_enabled           = true
    target_port                = 8080
    transport                  = "http"
    allow_insecure_connections = true

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas
    revision_suffix = var.image_tag

    container {
      name   = var.image_name
      image  = "${data.azurerm_container_registry.example.login_server}/${var.image_name}:${var.image_tag}"
      cpu    = var.cpu_cores
      memory = var.memory

      env {
        name        = "AZURE_STORAGE_CONNECTION_STRING"
        secret_name = local.storage_conn_secret_name
      }

      env {
        name  = "BLOB_CONTAINER_NAME"
        value = var.blob_container_name
      }

      env {
        name  = "APP_REVISION"
        value = var.image_tag
      }
    }

    http_scale_rule {
      name                = "http-scale"
      concurrent_requests = "50"
    }
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
