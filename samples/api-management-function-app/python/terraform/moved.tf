# This version of the sample creates its resources through modules. These moved blocks tell Terraform where each
# resource of the earlier version, which declared them in main.tf, lives now: applying this version over a deployment
# made with the earlier one moves those resources into the modules instead of destroying and recreating them.

moved {
  from = azurerm_api_management.main
  to   = module.api_management.azurerm_api_management.example
}

moved {
  from = azurerm_api_management_api.inventory
  to   = module.api_management.azurerm_api_management_api.inventory
}

moved {
  from = azurerm_api_management_api_policy.inventory
  to   = module.api_management.azurerm_api_management_api_policy.inventory
}

moved {
  from = azurerm_api_management_named_value.backend_secret
  to   = module.api_management.azurerm_api_management_named_value.backend_secret
}

moved {
  from = azurerm_api_management_product.partners
  to   = module.api_management.azurerm_api_management_product.partners
}

moved {
  from = azurerm_api_management_product_api.partners_inventory
  to   = module.api_management.azurerm_api_management_product_api.partners_inventory
}

moved {
  from = azurerm_api_management_subscription.partner
  to   = module.api_management.azurerm_api_management_subscription.partner
}

moved {
  from = azurerm_linux_function_app.inventory
  to   = module.function_app.azurerm_linux_function_app.example
}

moved {
  from = azurerm_service_plan.main
  to   = module.app_service_plan.azurerm_service_plan.example
}

moved {
  from = azurerm_storage_account.main
  to   = module.storage_account.azurerm_storage_account.example
}

