output "id" {
  value       = azurerm_cosmosdb_account.example.id
  description = "Specifies the resource id of the Cosmos DB account"
}

output "name" {
  value       = azurerm_cosmosdb_account.example.name
  description = "Specifies the name of the Cosmos DB account"
}

output "endpoint" {
  value       = azurerm_cosmosdb_account.example.endpoint
  description = "Specifies the endpoint of the Cosmos DB account"
}

output "primary_mongodb_connection_string" {
  value       = azurerm_cosmosdb_account.example.primary_mongodb_connection_string
  description = "Specifies the primary MongoDB connection string"
  sensitive   = true
}

output "database_name" {
  value       = azurerm_cosmosdb_mongo_database.example.name
  description = "Specifies the name of the MongoDB database"
}

output "collection_name" {
  value       = azurerm_cosmosdb_mongo_collection.example.name
  description = "Specifies the name of the MongoDB collection"
}
