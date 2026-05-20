resource "azurerm_application_insights" "example" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tags                          = var.tags
  application_type              = var.application_type
  workspace_id                  = var.workspace_id
  disable_ip_masking            = var.disable_ip_masking
  local_authentication_disabled = var.local_authentication_disabled
  internet_ingestion_enabled    = var.internet_ingestion_enabled
  internet_query_enabled        = var.internet_query_enabled

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}