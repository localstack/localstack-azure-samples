resource "azurerm_storage_account" "example" {
  name                = var.name
  resource_group_name = var.resource_group_name

  location                  = var.location
  account_kind              = var.account_kind
  account_tier              = var.account_tier
  account_replication_type  = var.replication_type
  is_hns_enabled            = var.is_hns_enabled
  shared_access_key_enabled = var.shared_access_key_enabled
  tags                      = var.tags

  network_rules {
    default_action             = (length(var.ip_rules) + length(var.virtual_network_subnet_ids)) > 0 ? "Deny" : var.default_action
    ip_rules                   = var.ip_rules
    virtual_network_subnet_ids = var.virtual_network_subnet_ids
    bypass                     = var.bypass
  }

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
