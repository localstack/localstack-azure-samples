resource "azurerm_linux_function_app" "example" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  service_plan_id               = var.service_plan_id
  storage_account_name          = var.storage_account_name
  storage_account_access_key    = var.storage_account_access_key
  https_only                    = var.https_only
  public_network_access_enabled = var.public_network_access_enabled
  functions_extension_version   = "~4"
  tags                          = var.tags

  identity {
    type         = var.identity_type
    identity_ids = var.identity_type == "UserAssigned" ? var.identity_ids : null
  }

  site_config {
    always_on                              = var.always_on
    minimum_tls_version                    = var.minimum_tls_version
    application_insights_connection_string = var.application_insights_connection_string

    # Exactly one of the two versions is set: the other one is null, which leaves it out.
    application_stack {
      python_version              = var.python_version
      dotnet_version              = var.dotnet_version
      use_dotnet_isolated_runtime = var.dotnet_version == null ? null : true
    }
  }

  app_settings = var.app_settings

  lifecycle {
    ignore_changes = [
      tags,
      # The provider writes AzureWebJobsStorage and FUNCTIONS_EXTENSION_VERSION from storage_account_name,
      # storage_account_access_key and functions_extension_version, and leaves both out of app_settings when it reads
      # the app back, so every plan would add them again. The values in app_settings still apply when the app is
      # created.
      app_settings["AzureWebJobsStorage"],
      app_settings["FUNCTIONS_EXTENSION_VERSION"],
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "example" {
  name                       = var.diagnostic_setting_name
  target_resource_id         = azurerm_linux_function_app.example.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}
