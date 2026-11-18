# This version of the sample creates its resources through modules. These moved blocks tell Terraform where each
# resource of the earlier version, which declared them in main.tf, lives now: applying this version over a deployment
# made with the earlier one moves those resources into the modules instead of destroying and recreating them.

moved {
  from = azurerm_application_insights.main
  to   = module.application_insights.azurerm_application_insights.example
}

moved {
  from = azurerm_eventhub.alerts
  to   = module.event_hubs.azurerm_eventhub.alerts
}

moved {
  from = azurerm_eventhub.payments
  to   = module.event_hubs.azurerm_eventhub.payments
}

moved {
  from = azurerm_eventhub_authorization_rule.alerts_send
  to   = module.event_hubs.azurerm_eventhub_authorization_rule.alerts_send
}

moved {
  from = azurerm_eventhub_authorization_rule.listen
  to   = module.event_hubs.azurerm_eventhub_authorization_rule.listen
}

moved {
  from = azurerm_eventhub_authorization_rule.send
  to   = module.event_hubs.azurerm_eventhub_authorization_rule.send
}

moved {
  from = azurerm_eventhub_consumer_group.groups["analytics"]
  to   = module.event_hubs.azurerm_eventhub_consumer_group.groups["analytics"]
}

moved {
  from = azurerm_eventhub_consumer_group.groups["audit"]
  to   = module.event_hubs.azurerm_eventhub_consumer_group.groups["audit"]
}

moved {
  from = azurerm_eventhub_consumer_group.groups["fraud-detector"]
  to   = module.event_hubs.azurerm_eventhub_consumer_group.groups["fraud-detector"]
}

moved {
  from = azurerm_eventhub_namespace.main
  to   = module.event_hubs.azurerm_eventhub_namespace.example
}

moved {
  from = azurerm_eventhub_namespace_authorization_rule.dashboard_listen
  to   = module.event_hubs.azurerm_eventhub_namespace_authorization_rule.dashboard_listen
}

moved {
  from = azurerm_eventhub_namespace_schema_group.payments
  to   = module.event_hubs.azurerm_eventhub_namespace_schema_group.payments
}

moved {
  from = azurerm_key_vault.main
  to   = module.key_vault.azurerm_key_vault.vault
}

moved {
  from = azurerm_key_vault_secret.eventhub_listen
  to   = module.key_vault.azurerm_key_vault_secret.secret["eventhub-listen-connection"]
}

moved {
  from = azurerm_key_vault_secret.eventhub_send
  to   = module.key_vault.azurerm_key_vault_secret.secret["eventhub-send-connection"]
}

moved {
  from = azurerm_key_vault_secret.storage
  to   = module.key_vault.azurerm_key_vault_secret.secret["storage-connection"]
}

moved {
  from = azurerm_linux_function_app.fraud
  to   = module.function_app.azurerm_linux_function_app.example
}

moved {
  from = azurerm_linux_web_app.dashboard
  to   = module.web_app.azurerm_linux_web_app.example
}

moved {
  from = azurerm_log_analytics_workspace.main
  to   = module.log_analytics.azurerm_log_analytics_workspace.example
}

moved {
  from = azurerm_service_plan.functions
  to   = module.function_plan.azurerm_service_plan.example
}

moved {
  from = azurerm_service_plan.web
  to   = module.web_plan.azurerm_service_plan.example
}

moved {
  from = azurerm_storage_account.main
  to   = module.storage_account.azurerm_storage_account.example
}

moved {
  from = azurerm_storage_container.capture
  to   = module.storage_account.azurerm_storage_container.example["payments-archive"]
}

