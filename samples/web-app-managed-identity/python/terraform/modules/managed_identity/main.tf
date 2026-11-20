# The identity a workload authenticates with. Role assignments are not created here: the role_assignment module
# grants the identity access to the resources the workload uses.
resource "azurerm_user_assigned_identity" "identity" {
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
