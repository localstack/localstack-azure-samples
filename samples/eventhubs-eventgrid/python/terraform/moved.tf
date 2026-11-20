# This version of the sample creates its resources through modules. These moved blocks tell Terraform where each
# resource of the earlier version, which declared them in main.tf, lives now: applying this version over a deployment
# made with the earlier one moves those resources into the modules instead of destroying and recreating them.

moved {
  from = azurerm_eventgrid_system_topic.namespace
  to   = module.event_grid.azurerm_eventgrid_system_topic.example
}

moved {
  from = azurerm_eventgrid_system_topic_event_subscription.capture_to_eventhub
  to   = module.event_grid.azurerm_eventgrid_system_topic_event_subscription.example
}

moved {
  from = azurerm_eventhub.curated
  to   = module.event_hubs.azurerm_eventhub.curated
}

moved {
  from = azurerm_eventhub.notifications
  to   = module.event_hubs.azurerm_eventhub.notifications
}

moved {
  from = azurerm_eventhub.telemetry
  to   = module.event_hubs.azurerm_eventhub.telemetry
}

moved {
  from = azurerm_eventhub_authorization_rule.telemetry_send
  to   = module.event_hubs.azurerm_eventhub_authorization_rule.telemetry_send
}

moved {
  from = azurerm_eventhub_consumer_group.capture_processor
  to   = module.event_hubs.azurerm_eventhub_consumer_group.capture_processor
}

moved {
  from = azurerm_eventhub_namespace.main
  to   = module.event_hubs.azurerm_eventhub_namespace.example
}

moved {
  from = azurerm_eventhub_namespace_authorization_rule.pipeline_listen
  to   = module.event_hubs.azurerm_eventhub_namespace_authorization_rule.pipeline_listen
}

moved {
  from = azurerm_linux_function_app.processor
  to   = module.function_app.azurerm_linux_function_app.example
}

moved {
  from = azurerm_service_plan.functions
  to   = module.app_service_plan.azurerm_service_plan.example
}

moved {
  from = azurerm_storage_account.main
  to   = module.storage_account.azurerm_storage_account.example
}

moved {
  from = azurerm_storage_container.capture
  to   = module.storage_account.azurerm_storage_container.example["telemetry-archive"]
}

