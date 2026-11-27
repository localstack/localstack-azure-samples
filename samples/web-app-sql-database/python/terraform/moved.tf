# This version of the sample creates its resources through modules. These moved blocks tell Terraform where each
# resource of the earlier version, which declared them in main.tf, lives now: applying this version over a deployment
# made with the earlier one moves those resources into the modules instead of destroying and recreating them.

moved {
  from = azurerm_key_vault.example
  to   = module.key_vault.azurerm_key_vault.example
}

moved {
  from = azurerm_key_vault_certificate.example
  to   = module.key_vault.azurerm_key_vault_certificate.example
}

moved {
  from = azurerm_key_vault_key.tde
  to   = module.key_vault.azurerm_key_vault_key.tde
}

moved {
  from = azurerm_key_vault_secret.sql_connection_string
  to   = module.key_vault.azurerm_key_vault_secret.sql_connection_string
}

moved {
  from = azurerm_linux_web_app.example
  to   = module.web_app.azurerm_linux_web_app.example
}

moved {
  from = azurerm_mssql_database.example
  to   = module.sql_server.azurerm_mssql_database.example
}

moved {
  from = azurerm_mssql_firewall_rule.example
  to   = module.sql_server.azurerm_mssql_firewall_rule.example
}

moved {
  from = azurerm_mssql_server.example
  to   = module.sql_server.azurerm_mssql_server.example
}

moved {
  from = azurerm_mssql_server_transparent_data_encryption.example
  to   = module.transparent_data_encryption.azurerm_mssql_server_transparent_data_encryption.example
}

moved {
  from = azurerm_service_plan.example
  to   = module.app_service_plan.azurerm_service_plan.example
}

moved {
  from = azurerm_user_assigned_identity.sql_server
  to   = module.sql_server_identity.azurerm_user_assigned_identity.identity
}

