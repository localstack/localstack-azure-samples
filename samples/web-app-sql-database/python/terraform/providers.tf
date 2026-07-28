terraform {
  required_version = ">=1.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Pinned below 4.81.0: azurerm >= ~4.61 strictly parses the `sid` (secret id)
      # returned for Key Vault certificates, and the LocalStack Azure emulator currently
      # returns the certificate id in that field. Bump back to =4.81.0 once the emulator
      # returns a proper `.../secrets/...` sid for certificates.
      version = "=4.60.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  # Set the hostname of the Azure Metadata Service (for example management.azure.com) 
  # used to obtain the Cloud Environment when using LocalStack's Azure emulator. 
  # This allows the provider to correctly identify the environment and avoid making calls to the real Azure endpoints. 
  metadata_host = "localhost.localstack.cloud:4566"

  # Set the subscription ID to a dummy value when using LocalStack's Azure emulator.
  subscription_id = "00000000-0000-0000-0000-000000000000"
}
