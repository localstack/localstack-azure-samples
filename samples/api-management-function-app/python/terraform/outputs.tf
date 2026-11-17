output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "function_app_name" {
  value = module.function_app.name
}

output "function_app_host" {
  value = module.function_app.default_hostname
}

output "apim_name" {
  value = module.api_management.name
}

output "gateway_url" {
  value = module.api_management.gateway_url
}

output "api_path" {
  value = module.api_management.api_path
}

output "product_id" {
  value = "inventory-partners"
}

output "subscription_id" {
  value = module.api_management.subscription_id
}

output "log_analytics_name" {
  value = module.log_analytics.name
}

output "application_insights_name" {
  value = module.application_insights.name
}
