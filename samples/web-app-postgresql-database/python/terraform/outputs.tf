output "resource_group_name" {
  value       = azurerm_resource_group.rg.name
  description = "The name of the resource group"
}

output "server_name" {
  value       = azurerm_postgresql_flexible_server.pg.name
  description = "The name of the PostgreSQL Flexible Server"
}

output "server_fqdn" {
  value       = azurerm_postgresql_flexible_server.pg.fqdn
  description = "The FQDN of the PostgreSQL server for client connections"
}

output "server_id" {
  value       = azurerm_postgresql_flexible_server.pg.id
  description = "The resource ID of the PostgreSQL server"
}

output "server_version" {
  value       = azurerm_postgresql_flexible_server.pg.version
  description = "PostgreSQL version"
}

output "database_name" {
  value       = azurerm_postgresql_flexible_server_database.primary_db.name
  description = "The name of the primary database"
}

output "secondary_database_name" {
  value       = azurerm_postgresql_flexible_server_database.secondary_db.name
  description = "The name of the secondary (analytics) database"
}

output "firewall_rule_names" {
  value = [
    azurerm_postgresql_flexible_server_firewall_rule.allow_all.name,
    azurerm_postgresql_flexible_server_firewall_rule.corporate.name,
    azurerm_postgresql_flexible_server_firewall_rule.vpn.name,
  ]
  description = "Names of all firewall rules"
}
