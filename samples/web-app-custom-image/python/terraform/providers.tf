terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=5.1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  # Dual-target, deliberately: nothing emulator-specific is hardcoded here. deploy.sh exports ARM_SUBSCRIPTION_ID and
  # ARM_TENANT_ID on both targets and, only when the active az cloud is LocalStack, ARM_METADATA_HOSTNAME (the
  # emulator's metadata endpoint, from which the provider discovers every other endpoint). Authentication uses the
  # Azure CLI session on both targets. Running terraform directly rather than through deploy.sh needs those variables
  # exported.
}