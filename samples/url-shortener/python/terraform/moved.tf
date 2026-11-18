# This version of the sample creates its resources through modules. These moved blocks tell Terraform where each
# resource of the earlier version, which declared them in main.tf, lives now: applying this version over a deployment
# made with the earlier one moves those resources into the modules instead of destroying and recreating them.

moved {
  from = azurerm_key_vault.main
  to   = module.key_vault.azurerm_key_vault.vault
}

moved {
  from = azurerm_key_vault_secret.pg_conn
  to   = module.key_vault.azurerm_key_vault_secret.secret["pg-conn"]
}

moved {
  from = azurerm_key_vault_secret.sign_key
  to   = module.key_vault.azurerm_key_vault_secret.secret["link-sign-key"]
}

moved {
  from = azurerm_linux_function_app.worker
  to   = module.function_app.azurerm_linux_function_app.example
}

moved {
  from = azurerm_linux_web_app.web
  to   = module.web_app.azurerm_linux_web_app.example
}

moved {
  from = azurerm_log_analytics_workspace.main
  to   = module.log_analytics_workspace.azurerm_log_analytics_workspace.example
}

moved {
  from = azurerm_postgresql_flexible_server.main
  to   = module.postgres_flexible_server.azurerm_postgresql_flexible_server.this
}

moved {
  from = azurerm_postgresql_flexible_server_database.clicks
  to   = module.postgres_flexible_server.azurerm_postgresql_flexible_server_database.this
}

moved {
  from = azurerm_postgresql_flexible_server_firewall_rule.allow_all
  to   = module.postgres_flexible_server.azurerm_postgresql_flexible_server_firewall_rule.allow_all
}

moved {
  from = azurerm_role_assignment.blob_contributor
  to   = module.storage_role_assignments["Storage Blob Data Contributor"].azurerm_role_assignment.assignment
}

moved {
  from = azurerm_role_assignment.kv_secrets_user
  to   = module.key_vault_secrets_user_role_assignment.azurerm_role_assignment.assignment
}

moved {
  from = azurerm_role_assignment.queue_contributor
  to   = module.storage_role_assignments["Storage Queue Data Contributor"].azurerm_role_assignment.assignment
}

moved {
  from = azurerm_role_assignment.sb_receiver
  to   = module.service_bus_role_assignments["Azure Service Bus Data Receiver"].azurerm_role_assignment.assignment
}

moved {
  from = azurerm_role_assignment.sb_sender
  to   = module.service_bus_role_assignments["Azure Service Bus Data Sender"].azurerm_role_assignment.assignment
}

moved {
  from = azurerm_role_assignment.table_contributor
  to   = module.storage_role_assignments["Storage Table Data Contributor"].azurerm_role_assignment.assignment
}

moved {
  from = azurerm_service_plan.main
  to   = module.app_service_plan.azurerm_service_plan.example
}

moved {
  from = azurerm_servicebus_namespace.main
  to   = module.service_bus.azurerm_servicebus_namespace.example
}

moved {
  from = azurerm_servicebus_queue.link_events
  to   = module.service_bus.azurerm_servicebus_queue.example["link-events"]
}

moved {
  from = azurerm_storage_container.qrcodes
  to   = module.storage_account.azurerm_storage_container.example["qrcodes"]
}

moved {
  from = azurerm_storage_queue.qrjobs
  to   = module.storage_account.azurerm_storage_queue.example["qrjobs"]
}

moved {
  from = azurerm_storage_table.links
  to   = module.storage_account.azurerm_storage_table.example["links"]
}

moved {
  from = azurerm_user_assigned_identity.main
  to   = module.managed_identity.azurerm_user_assigned_identity.identity
}

# The storage account's name is shorter than in the earlier version, whose name left no room for a prefix or suffix
# longer than the defaults within Azure's 24 characters. A new name means a new account: Terraform replaces it, and
# the container, queue, table and role assignments that belong to it, with empty ones.
moved {
  from = azurerm_storage_account.main
  to   = module.storage_account.azurerm_storage_account.example
}
