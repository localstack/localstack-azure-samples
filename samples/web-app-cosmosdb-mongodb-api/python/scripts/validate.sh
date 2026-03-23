#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
WEBAPP_SUBNET_NSG_NAME="${PREFIX}-webapp-subnet-nsg-${SUFFIX}"
PE_SUBNET_NSG_NAME="${PREFIX}-pe-subnet-nsg-${SUFFIX}"
NAT_GATEWAY_NAME="${PREFIX}-nat-gateway-${SUFFIX}"
VIRTUAL_NETWORK_NAME="${PREFIX}-vnet-${SUFFIX}"
PRIVATE_DNS_ZONE_NAME="privatelink.mongo.cosmos.azure.com"
PRIVATE_ENDPOINT_NAME="${PREFIX}-mongodb-pe-${SUFFIX}"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
WEBAPP_NAME="${PREFIX}-webapp-${SUFFIX}"
COSMOSDB_ACCOUNT_NAME="${PREFIX}-mongodb-${SUFFIX}"
MONGODB_DATABASE_NAME="sampledb"
COLLECTION_NAME="activities"
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
echo -e "\n[$WEBAPP_NAME] web app:\n"
az webapp show \
	--name "$WEBAPP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Azure CosmosDB account
echo -e "\n[$COSMOSDB_ACCOUNT_NAME] cosmosdb account:\n"
az cosmosdb show \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,DocumentEndpoint:documentEndpoint}' \
	--output table \
	--only-show-errors

# Check MongoDB database
echo -e "\n[$MONGODB_DATABASE_NAME] mongodb database:\n"
az cosmosdb mongodb database show \
	--name "$MONGODB_DATABASE_NAME" \
	--account-name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,ResourceGroup:resourceGroup}' \
	--output table \
	--only-show-errors

# Check MongoDB collection
echo -e "\n[$COLLECTION_NAME] mongodb collection:\n"
az cosmosdb mongodb collection show \
	--name "$COLLECTION_NAME" \
	--database-name "$MONGODB_DATABASE_NAME" \
	--account-name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Log Analytics Workspace
echo -e "\n[$LOG_ANALYTICS_NAME] log analytics workspace:\n"
az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup}' \
	--output table \
	--only-show-errors

# Check NAT Gateway
echo -e "\n[$NAT_GATEWAY_NAME] nat gateway:\n"
az network nat gateway show \
	--name "$NAT_GATEWAY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Virtual Network
echo -e "\n[$VIRTUAL_NETWORK_NAME] virtual network:\n"
az network vnet show \
	--name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Private DNS Zone
echo -e "\n[$PRIVATE_DNS_ZONE_NAME] private dns zone:\n"
az network private-dns zone show \
	--name "$PRIVATE_DNS_ZONE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,ResourceGroup:resourceGroup,RecordSets:recordSets,VirtualNetworkLinks:virtualNetworkLinks}' \
	--output table \
	--only-show-errors

# Check Private Endpoint
echo -e "\n[$PRIVATE_ENDPOINT_NAME] private endpoint:\n"
az network private-endpoint show \
	--name "$PRIVATE_ENDPOINT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Web App Subnet NSG
echo -e "\n[$WEBAPP_SUBNET_NSG_NAME] network security group:\n"
az network nsg show \
	--name "$WEBAPP_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Private Endpoint Subnet NSG
echo -e "\n[$PE_SUBNET_NSG_NAME] network security group:\n"
az network nsg show \
	--name "$PE_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# List resources
echo -e "\n[$RESOURCE_GROUP_NAME] all resources:\n"
az resource list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors