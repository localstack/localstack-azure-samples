resource "azurerm_application_insights" "example" {
  name                         = var.name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  tags                         = var.tags
  application_type             = var.application_type
  workspace_id                 = var.workspace_id
  ip_masking_enabled           = var.ip_masking_enabled
  local_authentication_enabled = var.local_authentication_enabled
  internet_ingestion_enabled   = var.internet_ingestion_enabled
  internet_query_enabled       = var.internet_query_enabled

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}