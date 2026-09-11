resource "azurerm_public_ip" "example" {
  name                = coalesce(var.public_ip_name, "${var.name}PublicIp")
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = var.public_ip_allocation_method
  sku                 = var.public_ip_sku
  zones               = var.zones
  tags                = var.tags

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

resource "azurerm_nat_gateway_public_ip_association" "example" {
  nat_gateway_id       = azurerm_nat_gateway.example.id
  public_ip_address_id = azurerm_public_ip.example.id
}

resource "azurerm_subnet_nat_gateway_association" "example" {
  for_each       = var.subnet_ids
  subnet_id      = each.value
  nat_gateway_id = azurerm_nat_gateway.example.id
}
