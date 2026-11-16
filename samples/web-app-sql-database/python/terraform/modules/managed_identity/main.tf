# The identity a workload authenticates with. Role assignments are not created here: the module that owns a
# target resource grants access on it (the Key Vault module for the deploying principal's write access), or
# the role_assignment module does it for a consumer such as the Web App.
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
