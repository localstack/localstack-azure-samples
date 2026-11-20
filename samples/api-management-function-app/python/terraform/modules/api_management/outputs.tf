output "id" {
  value       = azurerm_api_management.example.id
  description = "Specifies the resource id of the API Management service"
}

output "name" {
  value       = azurerm_api_management.example.name
  description = "Specifies the name of the API Management service"
}

output "gateway_url" {
  value       = azurerm_api_management.example.gateway_url
  description = "Specifies the URL of the gateway of the API Management service"
}

output "api_path" {
  value       = azurerm_api_management_api.inventory.path
  description = "Specifies the URL suffix of the API on the gateway"
}

output "product_id" {
  value       = azurerm_api_management_product.partners.product_id
  description = "Specifies the id of the product the partners subscribe to"
}

output "subscription_id" {
  value       = azurerm_api_management_subscription.partner.subscription_id
  description = "Specifies the id of the subscription whose key clients present"
}
