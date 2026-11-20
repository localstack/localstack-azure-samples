locals {
  # The Consumption tier doesn't support the collection of resource logs, so its diagnostic setting sends metrics only;
  # on the other tiers GatewayLogs records every request through the gateway
  log_categories = var.log_categories != null ? var.log_categories : (startswith(var.sku_name, "Consumption") ? [] : ["GatewayLogs"])
}

# The Consumption tier provisions in minutes on Azure; the classic tiers take the better part of an hour.
resource "azurerm_api_management" "example" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.sku_name
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# The shared secret lives in a secret named value; the policy refers to it as {{backend-secret}}.
resource "azurerm_api_management_named_value" "backend_secret" {
  name                = var.named_value_id
  display_name        = var.named_value_id
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.example.name
  secret              = true
  value               = var.backend_secret
}

# The API is imported from the OpenAPI document shared with the other deployment variants, so its operations come from
# the document. The backend is the Function App.
resource "azurerm_api_management_api" "inventory" {
  name                  = var.api_id
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.example.name
  revision              = "1"
  display_name          = "Inventory API"
  description           = "Stock levels served by an Azure Function App and published through Azure API Management."
  path                  = var.api_path
  protocols             = ["https"]
  service_url           = var.service_url
  subscription_required = true

  import {
    content_format = "openapi+json"
    content_value  = var.open_api_document
  }
}

# Policies are validated when they are saved, and this one references the named value, so the named value has to exist
# first.
resource "azurerm_api_management_api_policy" "inventory" {
  api_name            = azurerm_api_management_api.inventory.name
  api_management_name = azurerm_api_management.example.name
  resource_group_name = var.resource_group_name
  xml_content         = var.api_policy

  depends_on = [azurerm_api_management_named_value.backend_secret]
}

resource "azurerm_api_management_product" "partners" {
  product_id            = var.product_id
  api_management_name   = azurerm_api_management.example.name
  resource_group_name   = var.resource_group_name
  display_name          = "Inventory Partners"
  description           = "Partners reading stock levels through the Inventory API"
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "partners_inventory" {
  api_name            = azurerm_api_management_api.inventory.name
  product_id          = azurerm_api_management_product.partners.product_id
  api_management_name = azurerm_api_management.example.name
  resource_group_name = var.resource_group_name
}

# The subscription's key is what clients present. Its scope is the product, so the key opens every API the product
# contains and nothing else.
resource "azurerm_api_management_subscription" "partner" {
  api_management_name = azurerm_api_management.example.name
  resource_group_name = var.resource_group_name
  subscription_id     = var.subscription_id
  display_name        = "Partner subscription"
  product_id          = azurerm_api_management_product.partners.id
  state               = "active"
}

resource "azurerm_monitor_diagnostic_setting" "example" {
  name                           = var.diagnostic_setting_name
  target_resource_id             = azurerm_api_management.example.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = var.log_analytics_destination_type

  dynamic "enabled_log" {
    for_each = toset(local.log_categories)
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
