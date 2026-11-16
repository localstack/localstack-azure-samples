output "resource_group_name" {
  value = azurerm_resource_group.example.name
}

output "storage_account_name" {
  value = module.storage_account.name
}

output "app_service_plan_name" {
  value = module.app_service_plan.name
}

output "function_app_name" {
  value = module.function_app.name
}

output "function_app_url" {
  value = "https://${module.function_app.default_hostname}"
}

output "log_analytics_name" {
  value = module.log_analytics.name
}

output "application_insights_name" {
  value = module.application_insights.name
}
