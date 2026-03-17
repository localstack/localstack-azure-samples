resource "azurerm_storage_account" "example" {
  name                = var.name
  resource_group_name = var.resource_group_name

  location                         = var.location
  account_kind                     = var.account_kind
  account_tier                     = var.account_tier
  account_replication_type         = var.replication_type
  access_tier                      = var.access_tier
  is_hns_enabled                   = var.is_hns_enabled
  shared_access_key_enabled        = var.shared_access_key_enabled
  min_tls_version                  = var.min_tls_version
  https_traffic_only_enabled       = var.https_traffic_only_enabled
  allow_nested_items_to_be_public  = var.allow_blob_public_access
  cross_tenant_replication_enabled = var.cross_tenant_replication_enabled
  public_network_access_enabled    = var.public_network_access_enabled
  tags                             = var.tags

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

resource "azurerm_monitor_diagnostic_setting" "blob" {
  name                       = "DiagnosticsSettings-blobService"
  target_resource_id         = "${azurerm_storage_account.example.id}/blobServices/default/"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "queue" {
  name                       = "DiagnosticsSettings-queueService"
  target_resource_id         = "${azurerm_storage_account.example.id}/queueServices/default/"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "table" {
  name                       = "DiagnosticsSettings-tableService"
  target_resource_id         = "${azurerm_storage_account.example.id}/tableServices/default/"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "file" {
  name                       = "DiagnosticsSettings-fileService"
  target_resource_id         = "${azurerm_storage_account.example.id}/fileServices/default/"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}
