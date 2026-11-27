terraform {
  required_version = ">=1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=5.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "=3.9.0"
    }

    # Absorbs the propagation delay of the deploying principal's Key Vault role assignment before the secrets are
    # written (see modules/key_vault)
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
  }

  # Dual-target, deliberately: nothing emulator-specific is hardcoded here. deploy.sh exports ARM_SUBSCRIPTION_ID and
  # ARM_TENANT_ID on both targets and, only when the active az cloud is LocalStack, ARM_METADATA_HOSTNAME (the
  # emulator's metadata endpoint, from which the provider discovers every other endpoint). Authentication uses the
  # Azure CLI session on both targets. Running terraform directly rather than through deploy.sh needs those variables
  # exported.
}
