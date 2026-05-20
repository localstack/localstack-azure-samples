resource "azurerm_public_ip_prefix" "example" {
  name                = var.public_ip_prefix_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku_name
  zones               = var.zones
  tags                = var.tags
  prefix_length       = var.public_ip_prefix_length

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_nat_gateway" "example" {
  name                    = var.name
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = var.sku_name
  idle_timeout_in_minutes = var.idle_timeout_in_minutes
  zones                   = var.zones
  tags                    = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_nat_gateway_public_ip_prefix_association" "example" {
  nat_gateway_id       = azurerm_nat_gateway.example.id
  public_ip_prefix_id = azurerm_public_ip_prefix.example.id
}

resource "azurerm_subnet_nat_gateway_association" "example" {
  for_each       = var.subnet_ids
  subnet_id      = each.value
  nat_gateway_id = azurerm_nat_gateway.example.id
}
