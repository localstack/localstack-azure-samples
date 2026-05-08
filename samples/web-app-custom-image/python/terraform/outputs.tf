output "resource_group_name" {
  value = local.resource_group_name
}

output "container_registry_name" {
  value = module.container_registry.name
}

output "container_registry_login_server" {
  value = module.container_registry.login_server
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