terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    # time_sleep holds the module's completion until the role assignment has had time to propagate.
    time = {
      source = "hashicorp/time"
    }
  }
}
