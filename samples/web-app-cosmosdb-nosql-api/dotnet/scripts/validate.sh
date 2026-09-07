#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
WEB_APP_NAME="${PREFIX}-webapp-nosql-${SUFFIX}"
APP_SERVICE_PLAN_NAME="${WEB_APP_NAME}"
COSMOSDB_ACCOUNT_NAME="${WEB_APP_NAME}"

# Check resource group
echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
az group show \
	--name "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check App Service Plan
echo -e "\n[$APP_SERVICE_PLAN_NAME] app service plan:\n"
az appservice plan show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_SERVICE_PLAN_NAME" \
	--output table \
	--only-show-errors

# Check Azure Web App
echo -e "\n[$WEB_APP_NAME] web app:\n"
az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,State:state,Location:location,DefaultHostName:defaultHostName}' \
	--output table \
	--only-show-errors

# Check Azure Cosmos DB account
echo -e "\n[$COSMOSDB_ACCOUNT_NAME] cosmos db account:\n"
az cosmosdb show \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,DocumentEndpoint:documentEndpoint,Kind:kind}' \
	--output table \
	--only-show-errors

# List resources
echo -e "\n[$RESOURCE_GROUP_NAME] all resources:\n"
az resource list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors
