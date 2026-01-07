#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='northeurope'
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}"
FUNCTION_APP_NAME="${PREFIX}-functionapp-${SUFFIX}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
RUNTIME="python"
RUNTIME_VERSION="3.12"
INPUT_STORAGE_CONTAINER_NAME='input'
OUTPUT_STORAGE_CONTAINER_NAME='output'
ZIPFILE="function_app.zip"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
ENVIRONMENT=$(az account show --query environmentName --output tsv)
RETRY_COUNT=3
SLEEP=5

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	azlocal start_interception
else
	echo "Using standard az for AzureCloud environment."
fi

AZ="az"

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

# Construct the storage connection string for LocalStack
STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT_NAME;AccountKey=$STORAGE_ACCOUNT_KEY;EndpointSuffix=core.windows.net"
echo "Storage connection string constructed: [$STORAGE_CONNECTION_STRING]"

# Get the storage account resource ID
STORAGE_ACCOUNT_RESOURCE_ID=$($AZ storage account show \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "id" \
	--output tsv \
	--only-show-errors)

if [ -n "$STORAGE_ACCOUNT_RESOURCE_ID" ]; then
	echo "Storage account resource ID retrieved successfully: $STORAGE_ACCOUNT_RESOURCE_ID"
else
	echo "Failed to retrieve storage account resource ID."
	exit 1
fi

# Get the storage account blob primary endpoint
AZURE_STORAGE_ACCOUNT_URL=$($AZ storage account show \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "primaryEndpoints.blob" \
	--output tsv \
	--only-show-errors)

if [ -n "$AZURE_STORAGE_ACCOUNT_URL" ]; then
	echo "Storage account blob primary endpoint retrieved successfully: $AZURE_STORAGE_ACCOUNT_URL"
else
	echo "Failed to retrieve storage account blob primary endpoint."
	exit 1
fi

# Check if the input blob container exists
echo "Checking if input blob container [$INPUT_STORAGE_CONTAINER_NAME] exists in the [$STORAGE_ACCOUNT_NAME] storage account..."
$AZ storage container show \
	--name "$INPUT_STORAGE_CONTAINER_NAME" \
	--account-name "$STORAGE_ACCOUNT_NAME" \
	--account-key "$STORAGE_ACCOUNT_KEY" &>/dev/null

if [[ $? != 0 ]]; then

	# Create input blob container
	echo "Creating input blob container [$INPUT_STORAGE_CONTAINER_NAME] in the [$STORAGE_ACCOUNT_NAME] storage account..."
	$AZ storage container create \
		--name "$INPUT_STORAGE_CONTAINER_NAME" \
		--account-name "$STORAGE_ACCOUNT_NAME" \
		--account-key "$STORAGE_ACCOUNT_KEY"

	if [ $? -eq 0 ]; then
		echo "Input blob container [$INPUT_STORAGE_CONTAINER_NAME] created successfully in the [$STORAGE_ACCOUNT_NAME] storage account."
	else
		echo "Failed to create input blob container [$INPUT_STORAGE_CONTAINER_NAME] in the [$STORAGE_ACCOUNT_NAME] storage account."
		exit 1
	fi
fi

# Check if the output blob container exists
echo "Checking if output blob container [$OUTPUT_STORAGE_CONTAINER_NAME] exists in the [$STORAGE_ACCOUNT_NAME] storage account..."
$AZ storage container show \
	--name "$OUTPUT_STORAGE_CONTAINER_NAME" \
	--account-name "$STORAGE_ACCOUNT_NAME" \
	--account-key "$STORAGE_ACCOUNT_KEY" &>/dev/null

if [[ $? != 0 ]]; then
	# Create output blob container
	echo "Creating output blob container [$OUTPUT_STORAGE_CONTAINER_NAME] in the [$STORAGE_ACCOUNT_NAME] storage account..."
	$AZ storage container create \
		--name "$OUTPUT_STORAGE_CONTAINER_NAME" \
		--account-name "$STORAGE_ACCOUNT_NAME" \
		--account-key "$STORAGE_ACCOUNT_KEY"

	if [ $? -eq 0 ]; then
		echo "Output blob container [$OUTPUT_STORAGE_CONTAINER_NAME] created successfully in the [$STORAGE_ACCOUNT_NAME] storage account."
	else
		echo "Failed to create output blob container [$OUTPUT_STORAGE_CONTAINER_NAME] in the [$STORAGE_ACCOUNT_NAME] storage account."
		exit 1
	fi
fi

# Check if the user-assigned managed identity already exists
echo "Checking if [$MANAGED_IDENTITY_NAME] user-assigned managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group..."

$AZ identity show \
	--name"$MANAGED_IDENTITY_NAME" \
	--resource-group $"$RESOURCE_GROUP_NAME" &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$MANAGED_IDENTITY_NAME] user-assigned managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$MANAGED_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the user-assigned managed identity
	$AZ identity create \
		--name "$MANAGED_IDENTITY_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--subscription "$SUBSCRIPTION_ID" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$MANAGED_IDENTITY_NAME] user-assigned managed identity successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$MANAGED_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$MANAGED_IDENTITY_NAME] user-assigned managed identity already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Retrieve the clientId of the user-assigned managed identity
echo "Retrieving clientId for [$MANAGED_IDENTITY_NAME] managed identity..."
CLIENT_ID=$($AZ identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query clientId \
	--output tsv)

if [[ -n $CLIENT_ID ]]; then
	echo "[$CLIENT_ID] clientId  for the [$MANAGED_IDENTITY_NAME] managed identity successfully retrieved"
else
	echo "Failed to retrieve clientId for the [$MANAGED_IDENTITY_NAME] managed identity"
	exit 1
fi

# Retrieve the principalId of the user-assigned managed identity
echo "Retrieving principalId for [$MANAGED_IDENTITY_NAME] managed identity..."
PRINCIPAL_ID=$($AZ identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query principalId \
	--output tsv)

if [[ -n $PRINCIPAL_ID ]]; then
	echo "[$PRINCIPAL_ID] principalId  for the [$MANAGED_IDENTITY_NAME] managed identity successfully retrieved"
else
	echo "Failed to retrieve principalId for the [$MANAGED_IDENTITY_NAME] managed identity"
	exit 1
fi

# Retrieve the resource id of the user-assigned managed identity
echo "Retrieving resource id for the [$MANAGED_IDENTITY_NAME] managed identity..."
IDENTITY_ID=$($AZ identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv)

if [[ -n $IDENTITY_ID ]]; then
	echo "Resource id for the [$MANAGED_IDENTITY_NAME] managed identity successfully retrieved"
else
	echo "Failed to retrieve the resource id for the [$MANAGED_IDENTITY_NAME] managed identity"
	exit 1
fi

# Create the function app
echo "Creating function app [$FUNCTION_APP_NAME]..."
$AZ functionapp create \
	--resource-group $RESOURCE_GROUP_NAME \
	--consumption-plan-location $LOCATION \
	--assign-identity "${IDENTITY_ID}" \
	--runtime $RUNTIME \
	--runtime-version $RUNTIME_VERSION \
	--functions-version 4 \
	--name $FUNCTION_APP_NAME \
	--os-type linux \
	--storage-account $STORAGE_ACCOUNT_NAME \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Function app [$FUNCTION_APP_NAME] created successfully."
else
	echo "Failed to create function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Assign the Storage Blob Data Contributor role to the managed identity with the storage account as scope
ROLE="Storage Blob Data Contributor"
echo "Checking if the managed identity with principal ID [$PRINCIPAL_ID] has the [$ROLE] role assignment on storage account [$STORAGE_ACCOUNT_NAME]..."
current=$($AZ role assignment list \
	--assignee "$PRINCIPAL_ID" \
	--scope "$STORAGE_ACCOUNT_RESOURCE_ID" \
	--query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == "$ROLE" ]]; then
	echo "Managed identity already has the [$ROLE] role assignment on storage account [$STORAGE_ACCOUNT_NAME]"
else
	echo "Managed identity does not have the [$ROLE] role assignment on storage account [$STORAGE_ACCOUNT_NAME]"
	echo "Creating role assignment: assigning [$ROLE] role to managed identity on storage account [$STORAGE_ACCOUNT_NAME]..."
	ATTEMPT=1
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		$AZ role assignment create \
			--assignee "$PRINCIPAL_ID" \
			--role "$ROLE" \
			--scope "$STORAGE_ACCOUNT_RESOURCE_ID" 1>/dev/null

		if [[ $? == 0 ]]; then
			break
		else
			if [ $ATTEMPT -lt $RETRY_COUNT ]; then
				echo "Role assignment failed. Waiting [$SLEEP] seconds before retry..."
				sleep $SLEEP
			fi
			ATTEMPT=$((ATTEMPT + 1))
		fi
	done

	if [[ $? == 0 ]]; then
		echo "Successfully assigned [$ROLE] role to managed identity on storage account [$STORAGE_ACCOUNT_NAME]"
	else
		echo "Failed to assign [$ROLE] role to managed identity on storage account [$STORAGE_ACCOUNT_NAME]"
		exit
	fi
fi

# Assign the Storage Queue Data Contributor role to the managed identity with the storage account as scope
ROLE="Storage Queue Data Contributor"
echo "Checking if the managed identity with principal ID [$PRINCIPAL_ID] has the [$ROLE] role assignment on storage account [$STORAGE_ACCOUNT_NAME]..."
current=$($AZ role assignment list \
	--assignee "$PRINCIPAL_ID" \
	--scope "$STORAGE_ACCOUNT_RESOURCE_ID" \
	--query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == "$ROLE" ]]; then
	echo "Managed identity already has the [$ROLE] role assignment on storage account [$STORAGE_ACCOUNT_NAME]"
else
	echo "Managed identity does not have the [$ROLE] role assignment on storage account [$STORAGE_ACCOUNT_NAME]"
	echo "Creating role assignment: assigning [$ROLE] role to managed identity on storage account [$STORAGE_ACCOUNT_NAME]..."
	ATTEMPT=1
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		$AZ role assignment create \
			--assignee "$PRINCIPAL_ID" \
			--role "$ROLE" \
			--scope "$STORAGE_ACCOUNT_RESOURCE_ID" 1>/dev/null

		if [[ $? == 0 ]]; then
			break
		else
			if [ $ATTEMPT -lt $RETRY_COUNT ]; then
				echo "Role assignment failed. Waiting [$SLEEP] seconds before retry..."
				sleep $SLEEP
			fi
			ATTEMPT=$((ATTEMPT + 1))
		fi
	done

	if [[ $? == 0 ]]; then
		echo "Successfully assigned [$ROLE] role to managed identity on storage account [$STORAGE_ACCOUNT_NAME]"
	else
		echo "Failed to assign [$ROLE] role to managed identity on storage account [$STORAGE_ACCOUNT_NAME]"
		exit
	fi
fi

# Set function app settings
echo "Setting function app settings for [$FUNCTION_APP_NAME]..."

# Set storage URIs based on environment
BLOB_SERVICE_URI="https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net"
QUEUE_SERVICE_URI="https://${STORAGE_ACCOUNT_NAME}.queue.core.windows.net"
TABLE_SERVICE_URI="https://${STORAGE_ACCOUNT_NAME}.table.core.windows.net"
	

$AZ functionapp config appsettings set \
	--name $FUNCTION_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	AZURE_CLIENT_ID="$CLIENT_ID" \
	AzureWebJobsStorage="$STORAGE_CONNECTION_STRING" \
	STORAGE_ACCOUNT_CONNECTION_STRING__blobServiceUri="$BLOB_SERVICE_URI" \
	STORAGE_ACCOUNT_CONNECTION_STRING__queueServiceUri="$QUEUE_SERVICE_URI" \
	STORAGE_ACCOUNT_CONNECTION_STRING__tableServiceUri="$TABLE_SERVICE_URI" \
	INPUT_STORAGE_CONTAINER_NAME="$INPUT_STORAGE_CONTAINER_NAME" \
	OUTPUT_STORAGE_CONTAINER_NAME="$OUTPUT_STORAGE_CONTAINER_NAME" \
	FUNCTIONS_WORKER_RUNTIME="$RUNTIME" \
	FUNCTIONS_EXTENSION_VERSION="~4" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Function app settings for [$FUNCTION_APP_NAME] set successfully."
else
	echo "Failed to set function app settings for [$FUNCTION_APP_NAME]."
	exit 1
fi

# CD into the function app directory
cd ../src || exit

# Remove any existing zip package of the function app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the function app
echo "Creating zip package of the function app..."
zip -r "$ZIPFILE" function_app.py host.json requirements.txt

# Deploy the function app
echo "Deploying function app [$FUNCTION_APP_NAME] with zip file [$ZIPFILE]..."
$AZ functionapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--src-path "$ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully."
else
	echo "Failed to deploy function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Remove the zip package of the function app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi
