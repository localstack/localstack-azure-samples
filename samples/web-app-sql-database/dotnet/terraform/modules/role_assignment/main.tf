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

# A new role assignment can take a while to apply on Azure. A caller that uses the role right after the assignment
# passes a propagation_delay and depends on this module, which completes only once the delay has passed.
resource "time_sleep" "propagation" {
  depends_on      = [azurerm_role_assignment.assignment]
  create_duration = var.propagation_delay
}
