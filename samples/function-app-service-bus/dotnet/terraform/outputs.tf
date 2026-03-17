output "resource_group_name" {
  value = local.resource_group_name
}

output "app_service_plan_name" {
  value = module.app_service_plan.name
}

output "function_app_name" {
  value = module.function_app.name
}

output "function_app_default_hostname" {
  value = module.function_app.default_hostname
}

output "service_bus_namespace_name" {
  value = module.service_bus_namespace.name
}