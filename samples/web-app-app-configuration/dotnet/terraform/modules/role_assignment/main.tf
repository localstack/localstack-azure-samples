# One Azure RBAC role assignment. Azure names role assignments with a GUID; the provider generates it, so a
# second apply converges on the same assignment instead of creating a duplicate.
resource "azurerm_role_assignment" "assignment" {
  scope                            = var.scope
  role_definition_name             = var.role_definition_name
  principal_id                     = var.principal_id
  principal_type                   = var.principal_type
  skip_service_principal_aad_check = var.skip_service_principal_aad_check
  description                      = var.description
}
