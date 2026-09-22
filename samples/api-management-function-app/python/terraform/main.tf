# Local Variables
locals {
  resource_group_name  = "${var.prefix}-rg"
  storage_account_name = "${var.prefix}invstorage${var.suffix}"
  app_service_plan     = "${var.prefix}-inventory-app-service-plan-${var.suffix}"
  function_app_name    = "${var.prefix}-inventory-functionapp-${var.suffix}"
  apim_name            = "${var.prefix}-inventory-apim-${var.suffix}"
  api_id               = "inventory-api"
  api_path             = "inventory"
  product_id           = "inventory-partners"
  subscription_id      = "partner-subscription"
  named_value_id       = "backend-secret"
}

# The shared secret the gateway adds to every backend call. The Function App checks it, and the
# gateway reads it from a secret named value, so neither the policy document nor any client ever
# contains it.
resource "random_password" "backend_secret" {
  length  = 32
  special = false
}

# ---------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
}

# ---------------------------------------------------------------------------
# Function App: the Inventory backend
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
}

resource "azurerm_linux_function_app" "inventory" {
  name                        = local.function_app_name
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  service_plan_id             = azurerm_service_plan.main.id
  storage_account_name        = azurerm_storage_account.main.name
  storage_account_access_key  = azurerm_storage_account.main.primary_access_key
  functions_extension_version = "~4"

  site_config {
    # On a Dedicated (App Service) plan the Functions host goes idle without this, and a gateway
    # call then waits for a cold start. Both sibling Function App samples set it.
    always_on = true

    application_stack {
      python_version = var.python_version
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME       = "python"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"
    # The Functions host parses AzureWebJobsStorage with the strict .NET storage clients, which
    # cannot parse the EndpointSuffix-with-port string the provider would compose on the
    # emulator - so the provider default is overridden with an explicit-endpoints connection,
    # as the url-shortener sibling does.
    AzureWebJobsStorage = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.main.name};AccountKey=${azurerm_storage_account.main.primary_access_key};BlobEndpoint=${azurerm_storage_account.main.primary_blob_endpoint};QueueEndpoint=${azurerm_storage_account.main.primary_queue_endpoint};TableEndpoint=${azurerm_storage_account.main.primary_table_endpoint}"
    # The same secret the gateway injects from its named value.
    BACKEND_SECRET = random_password.backend_secret.result
  }
}

# ---------------------------------------------------------------------------
# API Management
# ---------------------------------------------------------------------------
# The Consumption tier provisions in minutes on Azure; the classic tiers take the better part of
# an hour.
resource "azurerm_api_management" "main" {
  name                = local.apim_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.apim_sku_name
}

# The shared secret lives in a secret named value; the policy refers to it as {{backend-secret}}.
resource "azurerm_api_management_named_value" "backend_secret" {
  name                = local.named_value_id
  display_name        = local.named_value_id
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  secret              = true
  value               = random_password.backend_secret.result
}

# The API is imported from the OpenAPI document shared with the other deployment variants, so its
# operations come from the document. The backend is the Function App: the emulator answers on
# plain HTTP under its own hostname (use https:// on real Azure).
resource "azurerm_api_management_api" "inventory" {
  name                  = local.api_id
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "Inventory API"
  description           = "Stock levels served by an Azure Function App and published through Azure API Management."
  path                  = local.api_path
  protocols             = ["https"]
  service_url           = "${var.backend_scheme}://${azurerm_linux_function_app.inventory.default_hostname}/api"
  subscription_required = true

  import {
    content_format = "openapi+json"
    content_value  = file("${path.module}/../apim/openapi.json")
  }
}

# Policies are validated when they are saved, and this one references the named value, so the
# named value has to exist first.
resource "azurerm_api_management_api_policy" "inventory" {
  api_name            = azurerm_api_management_api.inventory.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  xml_content         = file("${path.module}/../apim/inventory-api-policy.xml")

  depends_on = [azurerm_api_management_named_value.backend_secret]
}

resource "azurerm_api_management_product" "partners" {
  product_id            = local.product_id
  api_management_name   = azurerm_api_management.main.name
  resource_group_name   = azurerm_resource_group.main.name
  display_name          = "Inventory Partners"
  description           = "Partners reading stock levels through the Inventory API"
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "partners_inventory" {
  api_name            = azurerm_api_management_api.inventory.name
  product_id          = azurerm_api_management_product.partners.product_id
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
}

# The subscription's key is what clients present. Its scope is the product, so the key opens
# every API the product contains and nothing else.
resource "azurerm_api_management_subscription" "partner" {
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  subscription_id     = local.subscription_id
  display_name        = "Partner subscription"
  product_id          = azurerm_api_management_product.partners.id
  state               = "active"
}
