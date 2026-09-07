output "resource_group_name" {
  value = local.resource_group_name
}

output "cosmosdb_account_name" {
  value = module.cosmosdb_mongodb.name
}

output "cosmosdb_document_endpoint" {
  value = module.cosmosdb_mongodb.endpoint
}

output "app_service_plan_name" {
  value = module.app_service_plan.name
}

output "web_app_name" {
  value = module.web_app.name
}

output "web_app_url" {
  value = module.web_app.default_hostname
}