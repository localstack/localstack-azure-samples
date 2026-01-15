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

  # LocalStack Azure emulator uses a fixed subscription id
  subscription_id = "00000000-0000-0000-0000-000000000000"

  # The following configs are required for local testing
  # Skip provider registration and authentication for LocalStack
  resource_provider_registrations = "none"

  # Use environment variables or static values for LocalStack
  tenant_id     = "00000000-0000-0000-0000-000000000000"
  client_id     = "00000000-0000-0000-0000-000000000000"
  client_secret = "fake-secret"

  # Disable authentication checks
  use_cli = false
  use_msi = false
}
