output "resource_group_name" {
  value = local.resource_group_name
}

output "mysql_server_name" {
  value = module.mysql_flexible_server.name
}

output "mysql_fqdn" {
  value = module.mysql_flexible_server.fqdn
}

output "mysql_database_name" {
  value = module.mysql_flexible_server.database_name
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
