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

# Check Azure SQL Server
$AZ sql server show \
--name local-sqlserver-test \
--resource-group local-rg \
--output table

# Check Azure SQL Database
$AZ sql db show \
--name PlannerDB \
--server local-sqlserver-test \
--resource-group local-rg \
--output table

# Check Azure Key Vault
$AZ keyvault show \
--name local-kv-test \
--resource-group local-rg \
--output table

# Check Key Vault secret
$AZ keyvault secret show \
--vault-name local-kv-test \
--name sql-connection-string \
--query "{name:name, enabled:attributes.enabled, created:attributes.created}" \
--output table