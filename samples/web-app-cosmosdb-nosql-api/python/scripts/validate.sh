#!/bin/bash

# Variables
# Check resource group
az group show \
--name local-rg \
--output table

# List resources
az resource list \
--resource-group local-rg \
--output table

# Check Azure Web App
az webapp show \
--name local-webapp-nosql-test \
--resource-group local-rg \
--output table

# Check Azure CosmosDB account
az cosmosdb show \
--name local-webapp-nosql-test \
--resource-group local-rg \
--output table

# Check database (not implemented yet)
# az database show \
# --name sampledb \
# --account-name local-webapp-nosqltest \
# --resource-group local-rg \
# --output table

# Check collection (not impleented yet)
# az cosmosdb collection show \
# --name activities \
# --database-name sampledb \
# --account-name local-webapp-nosql-test \
# --resource-group local-rg \
# --output table