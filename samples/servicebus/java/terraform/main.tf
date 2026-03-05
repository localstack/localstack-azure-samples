# Local Variables
locals {
  prefix                                       = lower(var.prefix)
  suffix                                       = lower(var.suffix)
  resource_group_name                          = "${local.prefix}-rg"
  servicebus_namespace_name                    = "${local.prefix}-sb-ns-${local.suffix}"
  servicebus_namespace_authorization_rule_name = "${local.prefix}-sb-ns-auth-rule-${local.suffix}"
  servicebus_queue_authorization_rule_name     = "${local.prefix}-sb-queue-auth-rule-${local.suffix}"
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}
resource "azurerm_servicebus_namespace" "example" {
  name                          = local.servicebus_namespace_name
  location                      = azurerm_resource_group.example.location
  resource_group_name           = azurerm_resource_group.example.name
  sku                           = var.servicebus_namespace_sku
  capacity                      = var.servicebus_namespace_capacity
  premium_messaging_partitions  = var.servicebus_namespace_premium_messaging_partitions
  local_auth_enabled            = var.servicebus_namespace_local_auth_enabled
  public_network_access_enabled = var.servicebus_namespace_public_network_access_enabled
  minimum_tls_version           = var.servicebus_namespace_minimum_tls_version
  tags                          = var.tags
}

resource "azurerm_servicebus_namespace_authorization_rule" "example" {
  name         = local.servicebus_namespace_authorization_rule_name
  namespace_id = azurerm_servicebus_namespace.example.id

  listen = true
  send   = true
  manage = false
}

resource "azurerm_servicebus_queue" "example" {
  name         = var.queue_name
  namespace_id = azurerm_servicebus_namespace.example.id

  lock_duration                           = var.servicebus_queue_lock_duration
  max_message_size_in_kilobytes           = var.servicebus_queue_max_message_size_in_kilobytes
  max_size_in_megabytes                   = var.servicebus_queue_max_size_in_megabytes
  requires_duplicate_detection            = var.servicebus_queue_requires_duplicate_detection
  requires_session                        = var.servicebus_queue_requires_session
  default_message_ttl                     = var.servicebus_queue_default_message_ttl
  dead_lettering_on_message_expiration    = var.servicebus_queue_dead_lettering_on_message_expiration
  duplicate_detection_history_time_window = var.servicebus_queue_duplicate_detection_history_time_window
  max_delivery_count                      = var.servicebus_queue_max_delivery_count
  status                                  = var.servicebus_queue_status
  batched_operations_enabled              = var.servicebus_queue_batched_operations_enabled
  auto_delete_on_idle                     = var.servicebus_queue_auto_delete_on_idle
  partitioning_enabled                    = var.servicebus_queue_partitioning_enabled
  express_enabled                         = var.servicebus_queue_express_enabled
  forward_to                              = var.servicebus_queue_forward_to
  forward_dead_lettered_messages_to       = var.servicebus_queue_forward_dead_lettered_messages_to
}


resource "azurerm_servicebus_queue_authorization_rule" "example" {
  name     = local.servicebus_queue_authorization_rule_name
  queue_id = azurerm_servicebus_queue.example.id

  listen = true
  send   = true
  manage = false
}