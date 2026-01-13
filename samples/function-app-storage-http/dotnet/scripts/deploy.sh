#!/bin/bash

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
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	AZ="azlocal"
	FUNC="funclocal"
else
	echo "Using standard az for AzureCloud environment."
	AZ="az"
	FUNC="func"
fi

# Create a resource group
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
$AZ group show --name $RESOURCE_GROUP_NAME &>/dev/null
if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	# Create the resource group
	$AZ group create \
		--name $RESOURCE_GROUP_NAME \
		--location $LOCATION \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created in the subscription [$SUBSCRIPTION_NAME]"
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]"
		exit
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists in the subscription [$SUBSCRIPTION_NAME]"
fi

# Create a storage account
echo "Checking if storage account [$STORAGE_ACCOUNT_NAME] exists in the resource group [$RESOURCE_GROUP_NAME]..."
$AZ storage account show \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No storage account [$STORAGE_ACCOUNT_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group."
	echo "Creating storage account [$STORAGE_ACCOUNT_NAME] in the [$RESOURCE_GROUP_NAME] resource group..."
	$AZ storage account create \
		--name $STORAGE_ACCOUNT_NAME \
		--location $LOCATION \
		--resource-group $RESOURCE_GROUP_NAME \
		--sku Standard_LRS 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Storage account [$STORAGE_ACCOUNT_NAME] created successfully in the [$RESOURCE_GROUP_NAME] resource group."
	else
		echo "Failed to create storage account [$STORAGE_ACCOUNT_NAME] in the [$RESOURCE_GROUP_NAME] resource group."
		exit 1
	fi
else
	echo "Storage account [$STORAGE_ACCOUNT_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group."
fi

# Get the storage account key
echo "Getting storage account key for [$STORAGE_ACCOUNT_NAME]..."
STORAGE_ACCOUNT_KEY=$($AZ storage account keys list \
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
$AZ functionapp create \
	--resource-group $RESOURCE_GROUP_NAME \
	--consumption-plan-location $LOCATION \
	--runtime $RUNTIME \
	--runtime-version $RUNTIME_VERSION \
	--functions-version 4 \
	--name $FUNCTION_APP_NAME \
	--os-type linux \
	--storage-account $STORAGE_ACCOUNT_NAME 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Function app [$FUNCTION_APP_NAME] created successfully."
else
	echo "Failed to create function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Construct the storage connection string for LocalStack
STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT_NAME;AccountKey=$STORAGE_ACCOUNT_KEY;EndpointSuffix=core.windows.net"

# Set function app settings
echo "Setting function app settings for [$FUNCTION_APP_NAME]..."
$AZ functionapp config appsettings set \
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
	FUNCTIONS_WORKER_RUNTIME="dotnet-isolated" 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Function app settings for [$FUNCTION_APP_NAME] set successfully."
else
	echo "Failed to set function app settings for [$FUNCTION_APP_NAME]."
	exit 1
fi

# CD into the function app directory
cd ../src/sample || exit

echo "Publishing function app [$FUNCTION_APP_NAME]..."
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	# Disable proxy for NuGet during build to avoid proxy interference
	NO_PROXY="api.nuget.org,*.nuget.org" no_proxy="api.nuget.org,*.nuget.org" $FUNC azure functionapp publish $FUNCTION_APP_NAME --dotnet-isolated #--verbose --debug
else
	$FUNC azure functionapp publish $FUNCTION_APP_NAME --dotnet-isolated #--verbose --debug
fi