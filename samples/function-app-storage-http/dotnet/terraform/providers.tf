terraform {
  required_version = ">=1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.14.0"
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
  # Uses fixed credentials that tflocal intercepts via HTTPS proxy
  subscription_id = "00000000-0000-0000-0000-000000000000"
  tenant_id       = "00000000-0000-0000-0000-000000000000"
  client_id       = "00000000-0000-0000-0000-000000000000"
  client_secret   = "fake-secret"

  # Skip provider registration - LocalStack doesn't support this API
  skip_provider_registration = true

  # Disable CLI/MSI authentication - use static credentials instead
  use_cli = false
  use_msi = false
}
