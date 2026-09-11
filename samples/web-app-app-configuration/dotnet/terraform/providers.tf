terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=5.1.0"
    }

    # The App Configuration key-values, including the two Key Vault references, are created as ARM child
    # resources (Microsoft.AppConfiguration/configurationStores/keyValues) with the AzAPI provider. The
    # azurerm resources azurerm_app_configuration_key and azurerm_app_configuration_feature cannot work
    # against the LocalStack emulator: after writing a key-value they need the App Configuration domain
    # suffix of the cloud environment, which an environment discovered from a metadata endpoint never
    # carries (see the README). AzAPI talks to Azure Resource Manager only, on both targets.
    azapi = {
      source  = "Azure/azapi"
      version = "=2.12.0"
    }

    # Absorbs the propagation delay of the deploying principal's Key Vault role assignment before the
    # secrets are written (see main.tf).
    time = {
      source  = "hashicorp/time"
      version = "=0.14.1"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # A destroyed store or vault is soft-deleted and keeps its name reserved: purge them so a later apply
    # can recreate them, and recover a soft-deleted vault of the same name instead of failing.
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    app_configuration {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = true
    }
  }

  # Dual-target, deliberately: nothing emulator-specific is hardcoded here. deploy.sh exports
  # ARM_SUBSCRIPTION_ID and ARM_TENANT_ID on both targets and, only when the active az cloud is
  # LocalStack, ARM_METADATA_HOSTNAME (the emulator's metadata endpoint, from which the provider
  # discovers every other endpoint). Authentication uses the Azure CLI session on both targets.
}

provider "azapi" {
  # AzAPI has no metadata discovery. deploy.sh exports ARM_RESOURCE_MANAGER_ENDPOINT,
  # ARM_ACTIVE_DIRECTORY_AUTHORITY_HOST, ARM_RESOURCE_MANAGER_AUDIENCE, ARM_DISABLE_INSTANCE_DISCOVERY and
  # ARM_SKIP_PROVIDER_REGISTRATION only for the emulator; against Azure the provider uses its public
  # cloud defaults. Authentication uses the Azure CLI session (use_cli defaults to true).
}
