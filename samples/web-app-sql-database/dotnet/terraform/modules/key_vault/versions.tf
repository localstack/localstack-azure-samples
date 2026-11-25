terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    # time_sleep absorbs the propagation delay of the deploying principal's role assignments before the key, the
    # secret and the certificate are written.
    time = {
      source = "hashicorp/time"
    }
  }
}
