output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "function_app_name" {
  value = azurerm_linux_function_app.inventory.name
}

output "function_app_host" {
  value = azurerm_linux_function_app.inventory.default_hostname
}

output "apim_name" {
  value = azurerm_api_management.main.name
}

output "gateway_url" {
  value = azurerm_api_management.main.gateway_url
}

output "api_path" {
  value = azurerm_api_management_api.inventory.path
}

output "product_id" {
  value = azurerm_api_management_product.partners.product_id
}

output "subscription_id" {
  value = azurerm_api_management_subscription.partner.subscription_id
}
