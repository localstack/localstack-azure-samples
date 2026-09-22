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
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  # Neither the metadata host nor the subscription is pinned here, so this one configuration
  # deploys to both targets:
  #
  #   * emulator - deploy.sh exports ARM_METADATA_HOSTNAME=localhost.localstack.cloud:4566 and
  #     ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 when `az account show` reports the
  #     LocalStack cloud, which is what points the provider at the emulator and stops it calling the
  #     real Azure endpoints;
  #   * real Azure - deploy.sh clears ARM_METADATA_HOSTNAME, so the provider uses the public
  #     cloud's metadata endpoint, and exports ARM_SUBSCRIPTION_ID from the account the Azure CLI is
  #     logged in to, because the pinned provider version requires a subscription.
  #
  # Running `terraform` directly rather than through deploy.sh needs those two variables exported
  # for an emulator deployment.
}
