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
--name local-webapp-test \
--resource-group local-rg \
--output table

# Check Azure SQL Server
az sql server show \
--name local-sqlserver-test \
--resource-group local-rg \
--output table

# Check Azure SQL Database
az sql db show \
--name PlannerDB \
--server local-sqlserver-test \
--resource-group local-rg \
--output table

# Check Azure Key Vault
az keyvault show \
--name local-kv-test \
--resource-group local-rg \
--output table

# Check Key Vault secret
az keyvault secret show \
--vault-name local-kv-test \
--name local-secret-test \
--query "{name:name, enabled:attributes.enabled, created:attributes.created}" \
--output table