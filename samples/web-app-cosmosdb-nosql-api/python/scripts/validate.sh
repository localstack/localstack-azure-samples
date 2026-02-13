#!/bin/bash

# Variables
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	AZ="azlocal"
else
	echo "Using standard az for AzureCloud environment."
	AZ="az"
fi

# Check resource group
$AZ group show \
--name local-rg \
--output table

# List resources
$AZ resource list \
--resource-group local-rg \
--output table

# Check Azure Web App
$AZ webapp show \
--name local-webapp-nosql-test \
--resource-group local-rg \
--output table

# Check Azure CosmosDB account
$AZ cosmosdb show \
--name local-webapp-nosql-test \
--resource-group local-rg \
--output table

# Check database (not implemented yet)
# $AZ database show \
# --name sampledb \
# --account-name local-webapp-nosqltest \
# --resource-group local-rg \
# --output table

# Check collection (not impleented yet)
# $AZ cosmosdb collection show \
# --name activities \
# --database-name sampledb \
# --account-name local-webapp-nosql-test \
# --resource-group local-rg \
# --output table