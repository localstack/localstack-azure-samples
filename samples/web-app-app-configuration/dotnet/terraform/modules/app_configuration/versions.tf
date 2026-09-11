terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    # The key-values are created as ARM child resources with AzAPI: the azurerm resources
    # azurerm_app_configuration_key and azurerm_app_configuration_feature cannot read them back against the
    # LocalStack emulator (they need the App Configuration domain suffix of the cloud environment, which an
    # environment discovered from a metadata endpoint does not carry). AzAPI talks to Azure Resource Manager
    # only, on both targets.
    azapi = {
      source = "Azure/azapi"
    }
  }
}
