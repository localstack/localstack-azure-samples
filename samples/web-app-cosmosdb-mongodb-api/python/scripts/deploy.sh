#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
DIAGNOSTIC_SETTINGS_NAME='default'
WEBAPP_SUBNET_NSG_NAME="${PREFIX}-webapp-subnet-nsg-${SUFFIX}"
PE_SUBNET_NSG_NAME="${PREFIX}-pe-subnet-nsg-${SUFFIX}"
NAT_GATEWAY_NAME="${PREFIX}-nat-gateway-${SUFFIX}"
PIP_PREFIX_NAME="${PREFIX}-nat-gateway-pip-prefix-${SUFFIX}"
VIRTUAL_NETWORK_NAME="${PREFIX}-vnet-${SUFFIX}"
VIRTUAL_NETWORK_ADDRESS_PREFIX="10.0.0.0/8"
WEBAPP_SUBNET_NAME="app-subnet"
WEBAPP_SUBNET_PREFIX="10.0.0.0/24"
PE_SUBNET_NAME="pe-subnet"
PE_SUBNET_PREFIX="10.0.1.0/24"
VIRTUAL_NETWORK_LINK_NAME="link-to-vnet"
PRIVATE_DNS_ZONE_NAME="privatelink.mongo.cosmos.azure.com"
PRIVATE_ENDPOINT_NAME="${PREFIX}-mongodb-pe-${SUFFIX}"
PRIVATE_ENDPOINT_GROUP="mongodb"
PRIVATE_DNS_ZONE_GROUP_NAME="default"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="S1"
WEBAPP_NAME="${PREFIX}-webapp-${SUFFIX}"
COSMOSDB_ACCOUNT_NAME="${PREFIX}-mongodb-${SUFFIX}"
MONGODB_API_VERSION="7.0"
MONGODB_DATABASE_NAME="sampledb"
COLLECTION_NAME="activities"
INDEXES='[{"key":{"keys":["_id"]}},{"key":{"keys":["username"]}},{"key":{"keys":["activity"]}},{"key":{"keys":["timestamp"]}}]'
SHARD="username"
THROUGHPUT=400
RUNTIME="python"
RUNTIME_VERSION="3.13"
LOGIN_NAME="paolo"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	AZ="azlocal"
else
	echo "Using standard az for AzureCloud environment."
	AZ="az"
fi

# Create a resource group
echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
$AZ group create \
	--name $RESOURCE_GROUP_NAME \
	--location $LOCATION \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Resource group [$RESOURCE_GROUP_NAME] created successfully."
else
	echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
	exit 1
fi

# Check if the CosmosDB account already exists
echo "Checking if [$COSMOSDB_ACCOUNT_NAME] CosmosDB account already exists in the [$RESOURCE_GROUP_NAME] resource group..."
$AZ cosmosdb show \
	--name $COSMOSDB_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$COSMOSDB_ACCOUNT_NAME] CosmosDB account already exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$COSMOSDB_ACCOUNT_NAME] CosmosDB account in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create a CosmosDB account with MongoDB kind
	$AZ cosmosdb create \
		--name $COSMOSDB_ACCOUNT_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--locations regionName=$LOCATION \
		--kind MongoDB \
		--server-version $MONGODB_API_VERSION \
		--default-consistency-level Session \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "[$COSMOSDB_ACCOUNT_NAME] CosmosDB account successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$COSMOSDB_ACCOUNT_NAME] CosmosDB account in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$COSMOSDB_ACCOUNT_NAME] CosmosDB account already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Retrieve account resource id
echo "Getting [$COSMOSDB_ACCOUNT_NAME] CosmosDB account resource id in the [$RESOURCE_GROUP_NAME] resource group..."
COSMOSDB_ACCOUNT_ID=$($AZ cosmosdb show \
	--name $COSMOSDB_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query id \
	--output tsv \
	--only-show-errors)

if [ -n "$COSMOSDB_ACCOUNT_ID" ]; then
	echo "CosmosDB account resource id retrieved successfully: $COSMOSDB_ACCOUNT_ID"
else
	echo "Failed to retrieve CosmosDB account resource id."
	exit 1
fi

# Retrieve document endpoint
echo "Getting [$COSMOSDB_ACCOUNT_NAME] CosmosDB account document endpoint in the [$RESOURCE_GROUP_NAME] resource group..."
DOCUMENT_ENDPOINT=$($AZ cosmosdb show \
	--name $COSMOSDB_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "documentEndpoint" \
	--output tsv \
	--only-show-errors)

if [ -n "$DOCUMENT_ENDPOINT" ]; then
	echo "Document endpoint retrieved successfully: $DOCUMENT_ENDPOINT"
else
	echo "Failed to retrieve document endpoint."
	exit 1
fi

# Check if the MongoDB database already exists
echo "Checking if [$MONGODB_DATABASE_NAME] MongoDB database already exists in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account..."
$AZ cosmosdb mongodb database show \
	--account-name $COSMOSDB_ACCOUNT_NAME \
	--name $MONGODB_DATABASE_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$MONGODB_DATABASE_NAME] MongoDB database already exists in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account"
	echo "Creating [$MONGODB_DATABASE_NAME] MongoDB database in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account..."

	# Create MongoDB database in the CosmosDB account
	$AZ cosmosdb mongodb database create \
		--account-name $COSMOSDB_ACCOUNT_NAME \
		--name $MONGODB_DATABASE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--output json \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "[$MONGODB_DATABASE_NAME] MongoDB database successfully created in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account"
	else
		echo "Failed to create [$MONGODB_DATABASE_NAME] MongoDB database in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account"
		exit 1
	fi
else
	echo "[$MONGODB_DATABASE_NAME] MongoDB database already exists in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account"
fi

# Check if the MongoDB database collection already exists
echo "Checking if [$COLLECTION_NAME] collection already exists in the [$MONGODB_DATABASE_NAME] MongoDB database..."
$AZ cosmosdb mongodb collection show \
	--account-name $COSMOSDB_ACCOUNT_NAME \
	--database-name $MONGODB_DATABASE_NAME \
	--name $COLLECTION_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$COLLECTION_NAME] collection already exists in the [$MONGODB_DATABASE_NAME] MongoDB database"
	echo "Creating [$COLLECTION_NAME] collection in the [$MONGODB_DATABASE_NAME] MongoDB database..."

	# Create a MongoDB database collection
	$AZ cosmosdb mongodb collection create \
		--account-name $COSMOSDB_ACCOUNT_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--database-name $MONGODB_DATABASE_NAME \
		--name $COLLECTION_NAME \
		--idx "$INDEXES" \
		--shard $SHARD \
		--throughput $THROUGHPUT \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "[$COLLECTION_NAME] collection successfully created in the [$MONGODB_DATABASE_NAME] MongoDB database"
	else
		echo "Failed to create [$COLLECTION_NAME] collection in the [$MONGODB_DATABASE_NAME] MongoDB database"
		exit 1
	fi
else
	echo "[$COLLECTION_NAME] collection already exists in the [$MONGODB_DATABASE_NAME] MongoDB database"
fi

# List CosmosDB connection strings
echo "Listing connection strings for CosmosDB account [$COSMOSDB_ACCOUNT_NAME]..."
COSMOSDB_CONNECTION_STRING=$($AZ cosmosdb keys list \
	--name $COSMOSDB_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--type connection-strings \
	--query "connectionStrings[0].connectionString" \
	--output tsv)

if [ $? -eq 0 ]; then
	echo "CosmosDB connection strings retrieved successfully."
	echo "Connection String: $COSMOSDB_CONNECTION_STRING"
else
	echo "Failed to retrieve CosmosDB connection strings."
fi

# Check if the network security group for the web app subnet already exists
echo "Checking if [$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
$AZ network nsg show \
	--name "$WEBAPP_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet..."

	# Create the network security group for the web app subnet
	$AZ network nsg create \
		--name "$WEBAPP_SUBNET_NSG_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Get the resource id of the network security group for the web app subnet
echo "Getting [$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet resource id in the [$RESOURCE_GROUP_NAME] resource group..."
WEBAPP_SUBNET_NSG_ID=$($AZ network nsg show \
	--name "$WEBAPP_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $WEBAPP_SUBNET_NSG_ID ]]; then
	echo "[$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet resource id retrieved successfully: $WEBAPP_SUBNET_NSG_ID"
else
	echo "Failed to retrieve [$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Check if the network security group for the private endpoint subnet already exists
echo "Checking if [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
$AZ network nsg show \
	--name "$PE_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet..."

	# Create the network security group for the private endpoint subnet
	$AZ network nsg create \
		--name "$PE_SUBNET_NSG_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Get the resource id of the network security group for the private endpoint subnet
echo "Getting [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet resource id in the [$RESOURCE_GROUP_NAME] resource group..."
PE_SUBNET_NSG_ID=$($AZ network nsg show \
	--name "$PE_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $PE_SUBNET_NSG_ID ]]; then
	echo "[$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet resource id retrieved successfully: $PE_SUBNET_NSG_ID"
else
	echo "Failed to retrieve [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Check if the public IP prefix for the NAT Gateway already exists
echo "Checking if [$PIP_PREFIX_NAME] public IP prefix for the NAT Gateway actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
$AZ network public-ip prefix show \
	--name "$PIP_PREFIX_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$PIP_PREFIX_NAME] public IP prefix for the NAT Gateway actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$PIP_PREFIX_NAME] public IP prefix for the NAT Gateway in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the public IP prefix for the NAT Gateway
	$AZ network public-ip prefix create \
		--name "$PIP_PREFIX_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--length 31 \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$PIP_PREFIX_NAME] public IP prefix for the NAT Gateway successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$PIP_PREFIX_NAME] public IP prefix for the NAT Gateway in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$PIP_PREFIX_NAME] public IP prefix for the NAT Gateway already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the NAT Gateway already exists
echo "Checking if [$NAT_GATEWAY_NAME] NAT Gateway actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
$AZ network nat gateway show \
	--name "$NAT_GATEWAY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$NAT_GATEWAY_NAME] NAT Gateway actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$NAT_GATEWAY_NAME] NAT Gateway in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the NAT Gateway
	$AZ network nat gateway create \
		--name "$NAT_GATEWAY_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--public-ip-prefixes "$PIP_PREFIX_NAME" \
		--idle-timeout 4 \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$NAT_GATEWAY_NAME] NAT Gateway successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$NAT_GATEWAY_NAME] NAT Gateway in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$NAT_GATEWAY_NAME] NAT Gateway already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the virtual network already exists
echo "Checking if [$VIRTUAL_NETWORK_NAME] virtual network actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
$AZ network vnet show \
	--name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$VIRTUAL_NETWORK_NAME] virtual network actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$VIRTUAL_NETWORK_NAME] virtual network in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the virtual network
	$AZ network vnet create \
		--name "$VIRTUAL_NETWORK_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--address-prefixes "$VIRTUAL_NETWORK_ADDRESS_PREFIX" \
		--subnet-name "$WEBAPP_SUBNET_NAME" \
		--subnet-prefix "$WEBAPP_SUBNET_PREFIX" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$VIRTUAL_NETWORK_NAME] virtual network successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$VIRTUAL_NETWORK_NAME] virtual network in the [$RESOURCE_GROUP_NAME] resource group"
		exit
	fi

	# Update the web app subnet to associate it with the NAT Gateway and the NSG
	echo "Associating [$WEBAPP_SUBNET_NAME] subnet with the [$NAT_GATEWAY_NAME] NAT Gateway and the [$WEBAPP_SUBNET_NSG_NAME] network security group..."

	# Update the web app subnet to associate it with the NAT Gateway and the NSG
	$AZ network vnet subnet update \
		--name "$WEBAPP_SUBNET_NAME" \
		--vnet-name "$VIRTUAL_NETWORK_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--nat-gateway "$NAT_GATEWAY_NAME" \
		--network-security-group "$WEBAPP_SUBNET_NSG_NAME" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$WEBAPP_SUBNET_NAME] subnet successfully associated with the [$NAT_GATEWAY_NAME] NAT Gateway and the [$WEBAPP_SUBNET_NSG_NAME] network security group"
	else
		echo "Failed to associate [$WEBAPP_SUBNET_NAME] subnet with the [$NAT_GATEWAY_NAME] NAT Gateway and the [$WEBAPP_SUBNET_NSG_NAME] network security group"
		exit 1
	fi
else
	echo "[$VIRTUAL_NETWORK_NAME] virtual network already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the subnet already exists
echo "Checking if [$PE_SUBNET_NAME] subnet actually exists in the [$VIRTUAL_NETWORK_NAME] virtual network..."
$AZ network vnet subnet show \
	--name "$PE_SUBNET_NAME" \
	--vnet-name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$PE_SUBNET_NAME] subnet actually exists in the [$VIRTUAL_NETWORK_NAME] virtual network"
	echo "Creating [$PE_SUBNET_NAME] subnet in the [$VIRTUAL_NETWORK_NAME] virtual network..."

	# Create the subnet
	$AZ network vnet subnet create \
		--name "$PE_SUBNET_NAME" \
		--vnet-name "$VIRTUAL_NETWORK_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--address-prefix "$PE_SUBNET_PREFIX" \
		--network-security-group "$PE_SUBNET_NSG_NAME" \
		--private-endpoint-network-policies "Disabled" \
		--private-link-service-network-policies "Disabled" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$PE_SUBNET_NAME] subnet successfully created in the [$VIRTUAL_NETWORK_NAME] virtual network"
	else
		echo "Failed to create [$PE_SUBNET_NAME] subnet in the [$VIRTUAL_NETWORK_NAME] virtual network"
		exit
	fi
else
	echo "[$PE_SUBNET_NAME] subnet already exists in the [$VIRTUAL_NETWORK_NAME] virtual network"
fi

# Retrieve the virtual network resource id
echo "Getting [$VIRTUAL_NETWORK_NAME] virtual network resource id in the [$RESOURCE_GROUP_NAME] resource group..."
VIRTUAL_NETWORK_ID=$($AZ network vnet show \
	--name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors \
	--query id \
	--output tsv)

if [[ -n $VIRTUAL_NETWORK_ID ]]; then
	echo "[$VIRTUAL_NETWORK_NAME] virtual network resource id retrieved successfully: $VIRTUAL_NETWORK_ID"
else
	echo "Failed to retrieve [$VIRTUAL_NETWORK_NAME] virtual network resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit
fi

# Check if the private DNS Zone already exists
echo "Checking if [$PRIVATE_DNS_ZONE_NAME] private DNS zone actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
$AZ network private-dns zone show \
	--name "$PRIVATE_DNS_ZONE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$PRIVATE_DNS_ZONE_NAME] private DNS zone actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$PRIVATE_DNS_ZONE_NAME] private DNS zone in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the private DNS Zone
	$AZ network private-dns zone create \
		--name "$PRIVATE_DNS_ZONE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$PRIVATE_DNS_ZONE_NAME] private DNS zone successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$PRIVATE_DNS_ZONE_NAME] private DNS zone in the [$RESOURCE_GROUP_NAME] resource group"
		exit
	fi
else
	echo "[$PRIVATE_DNS_ZONE_NAME] private DNS zone already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the virtual network link between the private DNS zone and the virtual network already exists
echo "Checking if [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network actually exists..."
$AZ network private-dns link vnet show \
	--name "$VIRTUAL_NETWORK_LINK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--zone-name "$PRIVATE_DNS_ZONE_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network actually exists"

	echo "Creating [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network..."

	# Create the virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network
	$AZ network private-dns link vnet create \
		--name "$VIRTUAL_NETWORK_LINK_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--zone-name "$PRIVATE_DNS_ZONE_NAME" \
		--virtual-network "$VIRTUAL_NETWORK_ID" \
		--registration-enabled false \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network successfully created"
	else
		echo "Failed to create [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network"
		exit
	fi
else
	echo "[$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network already exists"
fi

# Check if the private endpoint already exists
echo "Checking if private endpoint [$PRIVATE_ENDPOINT_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group..."
privateEndpointId=$($AZ network private-endpoint list \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors \
	--query "[?name=='$PRIVATE_ENDPOINT_NAME'].id" \
	--output tsv)

if [[ -z $privateEndpointId ]]; then
	echo "Private endpoint [$PRIVATE_ENDPOINT_NAME] does not exist in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$PRIVATE_ENDPOINT_NAME] private endpoint for the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create a private endpoint for the CosmosDB account
	$AZ network private-endpoint create \
		--name "$PRIVATE_ENDPOINT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--vnet-name "$VIRTUAL_NETWORK_NAME" \
		--subnet "$PE_SUBNET_NAME" \
		--private-connection-resource-id "$COSMOSDB_ACCOUNT_ID" \
		--group-id "$PRIVATE_ENDPOINT_GROUP" \
		--connection-name "mongodb-connection" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Private endpoint [$PRIVATE_ENDPOINT_NAME] successfully created for the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create a private endpoint for the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account in the [$RESOURCE_GROUP_NAME] resource group"
		exit
	fi
else
	echo "Private endpoint [$PRIVATE_ENDPOINT_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the private DNS zone grou is already created for the CosmosDB account private endpoint
echo "Checking if the private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PRIVATE_ENDPOINT_NAME] private endpoint already exists..."
NAME=$($AZ network private-endpoint dns-zone-group show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--endpoint-name "$PRIVATE_ENDPOINT_NAME" \
	--name "$PRIVATE_DNS_ZONE_GROUP_NAME" \
	--query name \
	--output tsv \
	--only-show-errors)

if [[ -z $NAME ]]; then
	echo "No private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PRIVATE_ENDPOINT_NAME] private endpoint actually exists"
	echo "Creating private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PRIVATE_ENDPOINT_NAME] private endpoint..."

	# Create the private DNS zone group for the CosmosDB account private endpoint
	$AZ network private-endpoint dns-zone-group create \
		--name "$PRIVATE_DNS_ZONE_GROUP_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--endpoint-name "$PRIVATE_ENDPOINT_NAME" \
		--private-dns-zone "$PRIVATE_DNS_ZONE_NAME" \
		--zone-name "mongodb-zone" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PRIVATE_ENDPOINT_NAME] private endpoint successfully created"
	else
		echo "Failed to create private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PRIVATE_ENDPOINT_NAME] private endpoint"
		exit
	fi
else
	echo "Private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PRIVATE_ENDPOINT_NAME] private endpoint already exists"
fi

# Create app service plan
echo "Creating app service plan [$APP_SERVICE_PLAN_NAME]..."
$AZ appservice plan create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_SERVICE_PLAN_NAME" \
	--location "$LOCATION" \
	--sku "$APP_SERVICE_PLAN_SKU" \
	--is-linux \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "app service plan [$APP_SERVICE_PLAN_NAME] created successfully."
else
	echo "Failed to create app service plan [$APP_SERVICE_PLAN_NAME]."
	exit 1
fi

# Get the app service plan resource id
echo "Getting [$APP_SERVICE_PLAN_NAME] app service plan resource id in the [$RESOURCE_GROUP_NAME] resource group..."
APP_SERVICE_PLAN_ID=$($AZ appservice plan show \
	--name "$APP_SERVICE_PLAN_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $APP_SERVICE_PLAN_ID ]]; then
	echo "[$APP_SERVICE_PLAN_NAME] app service plan resource id retrieved successfully: $APP_SERVICE_PLAN_ID"
else
	echo "Failed to retrieve [$APP_SERVICE_PLAN_NAME] app service plan resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Create the web app
echo "Creating web app [$WEBAPP_NAME]..."
$AZ webapp create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--plan "$APP_SERVICE_PLAN_NAME" \
	--name "$WEBAPP_NAME" \
	--runtime "$RUNTIME:$RUNTIME_VERSION" \
	--vnet "$VIRTUAL_NETWORK_NAME" \
	--subnet "$WEBAPP_SUBNET_NAME" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app [$WEBAPP_NAME] created successfully."
else
	echo "Failed to create web app [$WEBAPP_NAME]."
	exit 1
fi

# Enabling
echo "Enabling forced tunneling for web app [$WEBAPP_NAME] to route all outbound traffic through the virtual network..."

$AZ resource update \
	--ids "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.Web/sites/$WEBAPP_NAME" \
	--set properties.outboundVnetRouting.allTraffic=true \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Forced tunneling enabled for web app [$WEBAPP_NAME]."
else
	echo "Failed to enable forced tunneling for web app [$WEBAPP_NAME]."
	exit 1
fi

# Get the web app resource id
echo "Getting [$WEBAPP_NAME] web app resource id in the [$RESOURCE_GROUP_NAME] resource group..."
WEBAPP_ID=$($AZ webapp show \
	--name "$WEBAPP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $WEBAPP_ID ]]; then
	echo "[$WEBAPP_NAME] web app resource id retrieved successfully: $WEBAPP_ID"
else
	echo "Failed to retrieve [$WEBAPP_NAME] web app resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Set web app settings
echo "Setting web app settings for [$WEBAPP_NAME]..."
$AZ webapp config appsettings set \
	--name $WEBAPP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	COSMOSDB_CONNECTION_STRING="$COSMOSDB_CONNECTION_STRING" \
	COSMOSDB_DATABASE_NAME="$MONGODB_DATABASE_NAME" \
	COSMOSDB_COLLECTION_NAME="$COLLECTION_NAME" \
	LOGIN_NAME="$LOGIN_NAME" \
	WEBSITE_PORT="8000" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app settings for [$WEBAPP_NAME] set successfully."
else
	echo "Failed to set web app settings for [$WEBAPP_NAME]."
	exit 1
fi

# Check if the log analytics workspace already exists
echo "Checking if [$LOG_ANALYTICS_NAME] Log Analytics workspace already exists in the [$RESOURCE_GROUP_NAME] resource group..."
$AZ monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$LOG_ANALYTICS_NAME] Log Analytics workspace actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$LOG_ANALYTICS_NAME] Log Analytics workspace in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the Log Analytics workspace
	$AZ monitor log-analytics workspace create \
		--name "$LOG_ANALYTICS_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--query-access "Enabled" \
		--retention-time 30 \
		--sku "PerNode" \
		--only-show-errors 1>/dev/null
	
	if [[ $? == 0 ]]; then
		echo "[$LOG_ANALYTICS_NAME] Log Analytics workspace successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$LOG_ANALYTICS_NAME] Log Analytics workspace in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$LOG_ANALYTICS_NAME] Log Analytics workspace already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check whether the diagnostic settings for the web app already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEBAPP_NAME] web app already exist..."
$AZ monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$WEBAPP_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEBAPP_NAME] web app actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEBAPP_NAME] web app..."

	# Create the diagnostic settings for the web app to send logs to the Log Analytics workspace
	$AZ monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$WEBAPP_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "AppServiceHTTPLogs", "enabled": true},
			{"category": "AppServiceConsoleLogs", "enabled": true},
			{"category": "AppServiceAppLogs", "enabled": true},
			{"category": "AppServiceAuditLogs", "enabled": true},
			{"category": "AppServiceIPSecAuditLogs", "enabled": true},
			{"category": "AppServicePlatformLogs", "enabled": true},
			{"category": "AppServiceAuthenticationLogs", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null


	if [[ $? == 0 ]]; then	
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEBAPP_NAME] web app successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEBAPP_NAME] web app"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEBAPP_NAME] web app already exist"
fi

# Check whether the diagnostic settings for the app service plan already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] app service plan already exist..."
$AZ monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$APP_SERVICE_PLAN_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] app service plan actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] app service plan..."

	# Create the diagnostic settings for the app service plan to send logs to the Log Analytics workspace
	$AZ monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$APP_SERVICE_PLAN_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null
	
	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] app service plan successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] app service plan"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] app service plan already exist"
fi

# Check whether the diagnostic settings for the CosmosDB account already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account already exist..."
$AZ monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$COSMOSDB_ACCOUNT_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account..."

	# Create the diagnostic settings for the CosmosDB account to send logs to the Log Analytics workspace
	$AZ monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$COSMOSDB_ACCOUNT_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "DataPlaneRequests", "enabled": true},
			{"category": "MongoRequests", "enabled": true}
		]' \
		--metrics '[
			{"category": "Requests", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account already exist"
fi

# Check whether the diagnostic settings for the virtual network already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$VIRTUAL_NETWORK_NAME] virtual network already exist..."
$AZ monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$VIRTUAL_NETWORK_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$VIRTUAL_NETWORK_NAME] virtual network actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$VIRTUAL_NETWORK_NAME] virtual network..."

	# Create the diagnostic settings for the virtual network to send logs to the Log Analytics workspace
	$AZ monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$VIRTUAL_NETWORK_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "VMProtectionAlerts", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$VIRTUAL_NETWORK_NAME] virtual network successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$VIRTUAL_NETWORK_NAME] virtual network"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$VIRTUAL_NETWORK_NAME] virtual network already exist"
fi

# Check whether the diagnostic settings for the network security group for the web app subnet already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet already exist..."
$AZ monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$WEBAPP_SUBNET_NSG_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet..."

	# Create the diagnostic settings for the network security group for the web app subnet to send logs to the Log Analytics workspace
	$AZ monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$WEBAPP_SUBNET_NSG_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "NetworkSecurityGroupEvent", "enabled": true},
			{"category": "NetworkSecurityGroupRuleCounter", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEBAPP_SUBNET_NSG_NAME] network security group for the web app subnet already exist"
fi

# Check whether the diagnostic settings for the network security group for the private endpoint subnet already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet already exist..."
$AZ monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$PE_SUBNET_NSG_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet..."

	# Create the diagnostic settings for the network security group for the private endpoint subnet to send logs to the Log Analytics workspace
	$AZ monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$PE_SUBNET_NSG_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "NetworkSecurityGroupEvent", "enabled": true},
			{"category": "NetworkSecurityGroupRuleCounter", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet already exist"
fi

# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py mongodb.py static templates requirements.txt

# List the contents of the zip package
echo "Contents of the zip package [$ZIPFILE]:"
unzip -l "$ZIPFILE"

# Deploy the web app
echo "Deploying web app [$WEBAPP_NAME] with zip file [$ZIPFILE]..."
echo "Using standard $AZ webapp deploy command for AzureCloud environment."
$AZ webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEBAPP_NAME" \
	--src-path "$ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Print the list of resources in the resource group
echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table 
