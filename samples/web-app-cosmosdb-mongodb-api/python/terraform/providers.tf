terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
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
  # metadata_host="localhost.localstack.cloud:4566"

  # Set the subscription ID to a dummy value when using LocalStack's Azure emulator.
  # subscription_id = "00000000-0000-0000-0000-000000000000"
  subscription_id = "8a733b0d-47e2-42d3-a1a1-18eb300390d8"
}