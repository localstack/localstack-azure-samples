# Local Variables
locals {
  prefix                              = lower(var.prefix)
  suffix                              = lower(var.suffix)
  resource_group_name                 = "${var.prefix}-rg"
  log_analytics_name                  = "${local.prefix}-log-analytics-${local.suffix}"
  storage_account_name                = "${local.prefix}storage${local.suffix}"
  virtual_network_name                = "${local.prefix}-vnet-${local.suffix}"
  nat_gateway_name                    = "${local.prefix}-nat-gateway-${local.suffix}"
  service_bus_private_endpoint_name   = "${local.prefix}-service-bus-pe-${local.suffix}"
  blob_storage_private_endpoint_name  = "${local.prefix}-blob-storage-pe-${local.suffix}"
  queue_storage_private_endpoint_name = "${local.prefix}-queue-storage-pe-${local.suffix}"
  table_storage_private_endpoint_name = "${local.prefix}-table-storage-pe-${local.suffix}"
  func_subnet_nsg_name                = "${local.prefix}-func-subnet-nsg-${local.suffix}"
  pe_subnet_nsg_name                  = "${local.prefix}-pe-subnet-nsg-${local.suffix}"
  cosmosdb_account_name               = "${local.prefix}-mongodb-${local.suffix}"
  service_bus_namespace_name          = "${local.prefix}-service-bus-${local.suffix}"
  app_service_plan_name               = "${local.prefix}-plan-${local.suffix}"
  function_app_name                   = "${local.prefix}-func-${local.suffix}"
  application_insights_name           = "${local.prefix}-func-${local.suffix}"
  managed_identity_name               = "${local.prefix}-identity-${local.suffix}"
  private_dns_zone_group_name         = "private-dns-zone-group"
}

# Data Sources
data "azurerm_client_config" "current" {
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create a log analytics workspace
module "log_analytics_workspace" {
  source              = "./modules/log_analytics"
  name                = local.log_analytics_name
  location            = var.location
  resource_group_name = azurerm_resource_group.example.name
  tags                = var.tags
}

# Create a virtual network with subnets
module "virtual_network" {
  source                     = "./modules/virtual_network"
  resource_group_name        = azurerm_resource_group.example.name
  location                   = var.location
  vnet_name                  = local.virtual_network_name
  address_space              = var.vnet_address_space
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags

  subnets = [
    {
      name : var.func_subnet_name
      address_prefixes : var.func_subnet_address_prefix
      private_endpoint_network_policies : "Enabled"
      private_link_service_network_policies_enabled : false
      delegation : "Microsoft.Web/serverFarms"
    },
    {
      name : var.pe_subnet_name
      address_prefixes : var.pe_subnet_address_prefix
      private_endpoint_network_policies : "Enabled"
      private_link_service_network_policies_enabled : false
    }
  ]
}

# Create a network security group and associate it with the function app subnet
module "func_subnet_network_security_group" {
  source                     = "./modules/network_security_group"
  name                       = local.func_subnet_nsg_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = var.location
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
  subnet_ids = {
    (var.func_subnet_name) = module.virtual_network.subnet_ids[var.func_subnet_name]
  }
}

# Create a network security group and associate it with the private endpoint subnet
module "pe_subnet_network_security_group" {
  source                     = "./modules/network_security_group"
  name                       = local.pe_subnet_nsg_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = var.location
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
  subnet_ids = {
    (var.pe_subnet_name)     = module.virtual_network.subnet_ids[var.pe_subnet_name]
  }
}

# Create a NAT gateway and associate it with the default subnet
module "nat_gateway" {
  source                  = "./modules/nat_gateway"
  name                    = local.nat_gateway_name
  resource_group_name     = azurerm_resource_group.example.name
  location                = var.location
  sku_name                = var.nat_gateway_sku_name
  idle_timeout_in_minutes = var.nat_gateway_idle_timeout_in_minutes
  zones                   = var.nat_gateway_zones
  subnet_ids = {
    (var.func_subnet_name) = module.virtual_network.subnet_ids[var.func_subnet_name]
  }
  tags = var.tags
}

# Create a storage account
module "storage_account" {
  source                     = "./modules/storage_account"
  name                       = local.storage_account_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = var.location
  account_kind               = var.account_kind
  account_tier               = var.account_tier
  replication_type           = var.account_replication_type
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
}

# Create a private DNS zone for blob storage and link it to the virtual network
module "blob_storage_private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.example.name
  tags                = var.tags
  virtual_networks_to_link = {
    (module.virtual_network.name) = {
      subscription_id     = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.example.name
    }
  }
}

# Create a private endpoint for blob storage in the pe_subnet subnet
module "blob_storage_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = local.blob_storage_private_endpoint_name
  location                       = var.location
  resource_group_name            = azurerm_resource_group.example.name
  subnet_id                      = module.virtual_network.subnet_ids[var.pe_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.storage_account.id
  is_manual_connection           = false
  subresource_name               = "blob"
  private_dns_zone_group_name    = local.private_dns_zone_group_name
  private_dns_zone_group_ids     = [module.blob_storage_private_dns_zone.id]
}

# Create a private DNS zone for queue storage and link it to the virtual network
module "queue_storage_private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = azurerm_resource_group.example.name
  tags                = var.tags
  virtual_networks_to_link = {
    (module.virtual_network.name) = {
      subscription_id     = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.example.name
    }
  }
}

# Create a private endpoint for queue storage in the pe_subnet subnet
module "queue_storage_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = local.queue_storage_private_endpoint_name
  location                       = var.location
  resource_group_name            = azurerm_resource_group.example.name
  subnet_id                      = module.virtual_network.subnet_ids[var.pe_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.storage_account.id
  is_manual_connection           = false
  subresource_name               = "queue"
  private_dns_zone_group_name    = local.private_dns_zone_group_name
  private_dns_zone_group_ids     = [module.queue_storage_private_dns_zone.id]
}

# Create a private DNS zone for table storage and link it to the virtual network
module "table_storage_private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = "privatelink.table.core.windows.net"
  resource_group_name = azurerm_resource_group.example.name
  tags                = var.tags
  virtual_networks_to_link = {
    (module.virtual_network.name) = {
      subscription_id     = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.example.name
    }
  }
}

# Create a private endpoint for table storage in the pe_subnet subnet
module "table_storage_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = local.table_storage_private_endpoint_name
  location                       = var.location
  resource_group_name            = azurerm_resource_group.example.name
  subnet_id                      = module.virtual_network.subnet_ids[var.pe_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.storage_account.id
  is_manual_connection           = false
  subresource_name               = "table"
  private_dns_zone_group_name    = local.private_dns_zone_group_name
  private_dns_zone_group_ids     = [module.table_storage_private_dns_zone.id]
}

# Create a private DNS zone for the Service Bus namespace account and link it to the virtual network
module "service_bus_private_dns_zone" {
  source              = "./modules/private_dns_zone"
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.example.name
  tags                = var.tags
  virtual_networks_to_link = {
    (module.virtual_network.name) = {
      subscription_id     = data.azurerm_client_config.current.subscription_id
      resource_group_name = azurerm_resource_group.example.name
    }
  }
}

# Create a private endpoint for the Service Bus namespace account in the pe_subnet subnet
module "service_bus_private_endpoint" {
  source                         = "./modules/private_endpoint"
  name                           = local.service_bus_private_endpoint_name
  location                       = var.location
  resource_group_name            = azurerm_resource_group.example.name
  subnet_id                      = module.virtual_network.subnet_ids[var.pe_subnet_name]
  tags                           = var.tags
  private_connection_resource_id = module.service_bus_namespace.id
  is_manual_connection           = false
  subresource_name               = "namespace"
  private_dns_zone_group_name    = local.private_dns_zone_group_name
  private_dns_zone_group_ids     = [module.service_bus_private_dns_zone.id]
}

# Create Service Bus namespace resources using module
module "service_bus_namespace" {
  source                                  = "./modules/service_bus"
  name                                    = local.service_bus_namespace_name
  resource_group_name                     = azurerm_resource_group.example.name
  location                                = azurerm_resource_group.example.location
  sku                                     = var.service_bus_sku
  capacity                                = var.service_bus_capacity
  premium_messaging_partitions            = var.service_bus_premium_messaging_partitions
  local_auth_enabled                      = var.service_bus_local_auth_enabled
  public_network_access_enabled           = var.service_bus_public_network_access_enabled
  minimum_tls_version                     = var.minimum_tls_version
  log_analytics_workspace_id              = module.log_analytics_workspace.id
  tags                                    = var.tags
  queue_names                             = var.queue_names
  lock_duration                           = var.queue_lock_duration
  max_message_size_in_kilobytes           = var.queue_max_message_size_in_kilobytes
  max_size_in_megabytes                   = var.queue_max_size_in_megabytes
  requires_duplicate_detection            = var.queue_requires_duplicate_detection
  requires_session                        = var.queue_requires_session
  default_message_ttl                     = var.queue_default_message_ttl
  dead_lettering_on_message_expiration    = var.queue_dead_lettering_on_message_expiration
  duplicate_detection_history_time_window = var.queue_duplicate_detection_history_time_window
  max_delivery_count                      = var.queue_max_delivery_count
  status                                  = var.queue_status
  batched_operations_enabled              = var.queue_batched_operations_enabled
  auto_delete_on_idle                     = var.queue_auto_delete_on_idle
  partitioning_enabled                    = var.queue_partitioning_enabled
  express_enabled                         = var.queue_express_enabled
  forward_to                              = var.queue_forward_to
  forward_dead_lettered_messages_to       = var.queue_forward_dead_lettered_messages_to
}

# Create App Service Plan using module
module "app_service_plan" {
  source                     = "./modules/app_service_plan"
  name                       = local.app_service_plan_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  sku_name                   = var.sku_name
  os_type                    = var.os_type
  zone_balancing_enabled     = var.zone_balancing_enabled
  log_analytics_workspace_id = module.log_analytics_workspace.id
  tags                       = var.tags
}

# Create Application Insights
module "application_insights" {
  source              = "./modules/application_insights"
  name                = local.application_insights_name
  location            = var.location
  resource_group_name = azurerm_resource_group.example.name
  workspace_id        = module.log_analytics_workspace.id
  tags                = var.tags
}

# Create a user-assigned managed identity
module "managed_identity" {
  source                  = "./modules/managed_identity"
  name                    = local.managed_identity_name
  resource_group_name     = azurerm_resource_group.example.name
  location                = var.location
  storage_account_id      = module.storage_account.id
  application_insights_id = module.application_insights.id
  service_bus_id          = module.service_bus_namespace.id
  tags                    = var.tags
}

# Create Web App using module
module "function_app" {
  source                        = "./modules/function_app"
  name                          = local.function_app_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  service_plan_id               = module.app_service_plan.id
  storage_account_name          = module.storage_account.name
  storage_account_access_key    = module.storage_account.primary_access_key
  https_only                    = var.https_only
  virtual_network_subnet_id     = module.virtual_network.subnet_ids[var.func_subnet_name]
  vnet_route_all_enabled        = true
  public_network_access_enabled = var.public_network_access_enabled
  always_on                     = var.always_on
  http2_enabled                 = var.http2_enabled
  minimum_tls_version           = var.minimum_tls_version
  use_dotnet_isolated_runtime   = var.use_dotnet_isolated_runtime
  java_version                  = var.java_version
  node_version                  = var.node_version
  dotnet_version                = var.dotnet_version
  python_version                = var.python_version
  managed_identity_type         = var.managed_identity_type
  managed_identity_id           = var.managed_identity_type == "UserAssigned" ? module.managed_identity.id : null
  repo_url                      = var.repo_url
  log_analytics_workspace_id    = module.log_analytics_workspace.id
  tags                          = var.tags

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT                         = "false"
    AzureWebJobsStorage                                    = module.storage_account.primary_connection_string
    FUNCTIONS_WORKER_RUNTIME                               = var.functions_worker_runtime
    FUNCTIONS_EXTENSION_VERSION                            = var.functions_extension_version
    AZURE_CLIENT_ID                                        = module.managed_identity.client_id
    SERVICE_BUS_CONNECTION_STRING__fullyQualifiedNamespace = "${module.service_bus_namespace.name}.servicebus.windows.net"
    APPLICATIONINSIGHTS_CONNECTION_STRING                  = module.application_insights.connection_string
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING              = "ClientId=${module.managed_identity.client_id};Authorization=AAD"
    INPUT_QUEUE_NAME                                       = var.input_queue_name
    OUTPUT_QUEUE_NAME                                      = var.output_queue_name
    NAMES                                                  = var.names
    TIMER_SCHEDULE                                         = var.timer_schedule
  }
}