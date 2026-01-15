terraform {
  required_version = ">=1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.44.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  # LocalStack Azure emulator configuration
  # Use Azure CLI authentication (which azlocal intercepts)
  use_cli = true
  use_msi = false
  use_oidc = false
}
