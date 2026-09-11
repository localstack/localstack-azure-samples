terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    # time_sleep absorbs the propagation delay of the deploying principal's role assignment before the
    # secrets are written.
    time = {
      source = "hashicorp/time"
    }
  }
}
