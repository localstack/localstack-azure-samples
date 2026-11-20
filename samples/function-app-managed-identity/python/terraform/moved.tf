# This version of the sample creates its resources through modules. These moved blocks tell Terraform where each
# resource of the earlier version, which declared them in main.tf, lives now: applying this version over a deployment
# made with the earlier one moves those resources into the modules instead of destroying and recreating them.

moved {
  from = azurerm_linux_function_app.example
  to   = module.function_app.azurerm_linux_function_app.example
}

moved {
  from = azurerm_role_assignment.blob_contributor
  to   = module.storage_blob_data_contributor_role_assignment.azurerm_role_assignment.assignment
}

moved {
  from = azurerm_role_assignment.queue_contributor
  to   = module.storage_queue_data_contributor_role_assignment.azurerm_role_assignment.assignment
}

moved {
  from = azurerm_service_plan.example
  to   = module.app_service_plan.azurerm_service_plan.example
}

moved {
  from = azurerm_storage_account.example
  to   = module.storage_account.azurerm_storage_account.example
}

moved {
  from = azurerm_storage_container.input
  to   = module.storage_account.azurerm_storage_container.example["input"]
}

moved {
  from = azurerm_storage_container.output
  to   = module.storage_account.azurerm_storage_container.example["output"]
}

moved {
  from = azurerm_user_assigned_identity.identity[0]
  to   = module.managed_identity[0].azurerm_user_assigned_identity.identity
}

