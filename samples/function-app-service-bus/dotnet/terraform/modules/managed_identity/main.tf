
resource "azurerm_user_assigned_identity" "example" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_role_assignment" "storage_account_contributor_assignment" {
  scope                            = var.storage_account_id
  role_definition_name             = "Storage Account Contributor"
  principal_id                     = azurerm_user_assigned_identity.example.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "storage_blob_data_owner_assignment" {
  scope                            = var.storage_account_id
  role_definition_name             = "Storage Blob Data Owner"
  principal_id                     = azurerm_user_assigned_identity.example.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "storage_queue_data_contributor_assignment" {
  scope                            = var.storage_account_id
  role_definition_name             = "Storage Queue Data Contributor"
  principal_id                     = azurerm_user_assigned_identity.example.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "storage_table_data_contributor_assignment" {
  scope                            = var.storage_account_id
  role_definition_name             = "Storage Table Data Contributor"
  principal_id                     = azurerm_user_assigned_identity.example.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "service_bus_contributor_assignment" {
  scope                            = var.service_bus_id
  role_definition_name             = "Azure Service Bus Data Owner"
  principal_id                     = azurerm_user_assigned_identity.example.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "monitoring_metrics_publisher_assignment" {
  scope                            = var.application_insights_id
  role_definition_name             = "Monitoring Metrics Publisher"
  principal_id                     = azurerm_user_assigned_identity.example.principal_id
  skip_service_principal_aad_check = true
}
