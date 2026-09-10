resource "azurerm_private_dns_zone" "example" {
  name                = var.name
  resource_group_name = var.resource_group_name
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "example" {
  for_each = var.virtual_networks_to_link

  # Named like the links the Azure CLI and Bicep variants create, so all three provisioning modes
  # produce the same topology (the sample links exactly one virtual network).
  name                = "link-to-vnet"
  private_dns_zone_id = azurerm_private_dns_zone.example.id
  virtual_network_id  = "/subscriptions/${each.value.subscription_id}/resourceGroups/${each.value.resource_group_name}/providers/Microsoft.Network/virtualNetworks/${each.key}"

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
