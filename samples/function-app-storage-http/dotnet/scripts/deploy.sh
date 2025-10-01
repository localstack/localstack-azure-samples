#!/bin/bash

# Start azure CLI local mode session
azlocal start_interception

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
FUNCTION_APP_NAME="${PREFIX}-func-${SUFFIX}"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
RUNTIME="DOTNET-ISOLATED"
RUNTIME_VERSION="9"
PLAYER_NAMES="Alice,Anastasia,Paolo,Leo,Mia"
INPUT_STORAGE_CONTAINER_NAME="input" 
OUTPUT_STORAGE_CONTAINER_NAME="output" 
INPUT_QUEUE_NAME="input" 
OUTPUT_QUEUE_NAME="output" 
TRIGGER_QUEUE_NAME="trigger" 
INPUT_TABLE_NAME="scoreboards" 
OUTPUT_TABLE_NAME="winners" 

# Create a resource group
echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
az group create --name $RESOURCE_GROUP_NAME --location $LOCATION

if [ $? -eq 0 ]; then
	echo "Resource group [$RESOURCE_GROUP_NAME] created successfully."
else
	echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
	exit 1
fi

# Create a storage account
echo "Creating storage account [$STORAGE_ACCOUNT_NAME] in the [$RESOURCE_GROUP_NAME] resource group..."
az storage account create --name $STORAGE_ACCOUNT_NAME --location $LOCATION --resource-group $RESOURCE_GROUP_NAME --sku Standard_LRS

if [ $? -eq 0 ]; then
	echo "Storage account [$STORAGE_ACCOUNT_NAME] created successfully in the [$RESOURCE_GROUP_NAME] resource group."
else
	echo "Failed to create storage account [$STORAGE_ACCOUNT_NAME] in the [$RESOURCE_GROUP_NAME] resource group."
	exit 1
fi

# Get the storage account key
echo "Getting storage account key for [$STORAGE_ACCOUNT_NAME]..."
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
	--account-name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "[0].value" \
	--output tsv)

if [ -n "$STORAGE_ACCOUNT_KEY" ]; then
	echo "Storage account key retrieved successfully: [$STORAGE_ACCOUNT_KEY]"
else
	echo "Failed to retrieve storage account key."
	exit 1
fi

# Create the function app
echo "Creating function app [$FUNCTION_APP_NAME]..."
az functionapp create \
	--resource-group $RESOURCE_GROUP_NAME \
	--consumption-plan-location $LOCATION \
	--runtime $RUNTIME \
	--runtime-version $RUNTIME_VERSION \
	--functions-version 4 \
	--name $FUNCTION_APP_NAME \
	--os-type linux \
	--storage-account $STORAGE_ACCOUNT_NAME \
	--verbose \
	--debug

if [ $? -eq 0 ]; then
	echo "Function app [$FUNCTION_APP_NAME] created successfully."
else
	echo "Failed to create function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Construct the storage connection string for LocalStack
#STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT_NAME;AccountKey=$STORAGE_ACCOUNT_KEY;BlobEndpoint=https://${STORAGE_ACCOUNT_NAME}blob.localhost.localstack.cloud:4566;QueueEndpoint=https://${STORAGE_ACCOUNT_NAME}queue.localhost.localstack.cloud:4566;TableEndpoint=https://${STORAGE_ACCOUNT_NAME}table.localhost.localstack.cloud:4566"
STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT_NAME;AccountKey=$STORAGE_ACCOUNT_KEY;EndpointSuffix=core.windows.net"

# Set function app settings
echo "Setting function app settings for [$FUNCTION_APP_NAME]..."
az functionapp config appsettings set \
	--name $FUNCTION_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	AzureWebJobsStorage="$STORAGE_CONNECTION_STRING" \
	STORAGE_ACCOUNT_CONNECTION_STRING="$STORAGE_CONNECTION_STRING" \
	WEBSITE_CONTENTAZUREFILECONNECTIONSTRING="$STORAGE_CONNECTION_STRING" \
	INPUT_STORAGE_CONTAINER_NAME="$INPUT_STORAGE_CONTAINER_NAME" \
	OUTPUT_STORAGE_CONTAINER_NAME="$OUTPUT_STORAGE_CONTAINER_NAME" \
	INPUT_QUEUE_NAME="$INPUT_QUEUE_NAME" \
	OUTPUT_QUEUE_NAME="$OUTPUT_QUEUE_NAME" \
	TRIGGER_QUEUE_NAME="$TRIGGER_QUEUE_NAME" \
	INPUT_TABLE_NAME="$INPUT_TABLE_NAME" \
	OUTPUT_TABLE_NAME="$OUTPUT_TABLE_NAME" \
	PLAYER_NAMES="$PLAYER_NAMES" \
	TIMER_SCHEDULE="0 */1 * * * *" \
	FUNCTIONS_WORKER_RUNTIME="dotnet-isolated"

if [ $? -eq 0 ]; then
	echo "Function app settings for [$FUNCTION_APP_NAME] set successfully."
else
	echo "Failed to set function app settings for [$FUNCTION_APP_NAME]."
	exit 1
fi

# CD into the function app directory
cd ../src/sample || exit

# Publish the function app
echo "Publishing function app [$FUNCTION_APP_NAME]..."
funclocal azure functionapp publish $FUNCTION_APP_NAME --dotnet-isolated --verbose --debug

# Stop azure CLI local mode session
azlocal stop_interception