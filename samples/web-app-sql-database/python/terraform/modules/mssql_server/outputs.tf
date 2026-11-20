output "id" {
  value       = azurerm_mssql_server.example.id
  description = "Specifies the resource id of the SQL server"
}

output "name" {
  value       = azurerm_mssql_server.example.name
  description = "Specifies the name of the SQL server"
}

output "fully_qualified_domain_name" {
  value       = azurerm_mssql_server.example.fully_qualified_domain_name
  description = "Specifies the fully qualified domain name of the SQL server"
}

output "database_id" {
  value       = azurerm_mssql_database.example.id
  description = "Specifies the resource id of the SQL database"
}

output "database_name" {
  value       = azurerm_mssql_database.example.name
  description = "Specifies the name of the SQL database"
}
