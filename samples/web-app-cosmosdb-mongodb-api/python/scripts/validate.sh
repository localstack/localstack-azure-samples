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
--name local-webapp-test \
--resource-group local-rg \
--output table

# Check Azure CosmosDB account
$AZ cosmosdb show \
--name local-mongodb-test \
--resource-group local-rg \
--output table

# Check MongoDB database
$AZ cosmosdb mongodb database show \
--name sampledb \
--account-name local-mongodb-test \
--resource-group local-rg \
--output table

# Check MongoDB collection
$AZ cosmosdb mongodb collection show \
--name activities \
--database-name sampledb \
--account-name local-mongodb-test \
--resource-group local-rg \
--output table