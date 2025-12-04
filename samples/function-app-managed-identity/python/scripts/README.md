# Azure CLI Deployment

This directory includes Bash scripts designed for deploying and testing the sample Web App utilizing the `azlocal` CLI. Refer to the [Azure Functions App with Managed Identity](../README.md) guide for details about the sample application.

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [Azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [Python](https://www.python.org/downloads/): Python runtime (version 3.13 or above)
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The deployment script uses the `azlocal` CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

This CLI deployment creates the following Azure resources using direct Azure CLI commands:

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage with `input` and `output` containers for storing text blobs processed by the function app.
2. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): Defines the compute resources (CPU, memory, and scaling options) that host the Azure Functions app.
3. [Azure Functions App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview): Hosts the serverless application that processes text blobs. The function app uses managed identity to securely access the Azure Storage Account without requiring explicit credentials.
4. [Managed Identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview): Provides secure, credential-free authentication between the Azure Functions app and storage account. Supports both system-assigned and user-assigned identity types.
5. [Role Assignment](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments): Grants the Azure Functions app's managed identity the Storage Blob Data Contributor and Storage Queue Data Contributor roles, enabling read/write access to blob containers and queues for processing text data.

For more information on the sample application, see [Azure Functions App with Managed Identity](../README.md).

## Deployment Script 

## Automation Scripts

This sample provides two bash scripts to streamline the deployment process by automating the provisioning of Azure resources and the sample application:

- `user-assigned.sh`: Configures the Azure Functions App to authenticate with Azure Storage using a *user-assigned managed identity*
- `system-assigned.sh`: Configures the Azure Functions App to authenticate with Azure Storage using a *system-assigned managed identity*

These scripts eliminate manual configuration steps and enable one-command deployment of the entire infrastructure. For brevity, we only report the code of the `user-assigned.sh` script in this article.

```bash
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
	AZ="azlocal"
else
	echo "Using standard az for AzureCloud environment."
	AZ="az"
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
```

> [!NOTE]
> You can use the `azlocal` CLI as a drop-in replacement for the `az` CLI to direct all commands to the LocalStack for Azure emulator. Alternatively, run `azlocal start_interception` to automatically intercept and redirect all `az` commands to LocalStack. To revert back to the default behavior and send commands to the Azure cloud, run `azlocal stop_interception`.

## Deployment

You can set up the Azure emulator by utilizing LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/?__hstc=108988063.8aad2b1a7229945859f4d9b9bb71e05d.1743148429561.1758793541854.1758810151462.32&__hssc=108988063.3.1758810151462&__hsfp=3945774529) to obtain your Auth Token and specify it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure-alpha). To pull the Azure Docker image, execute the following command:

```bash
docker pull localstack/localstack-azure-alpha
```

Start the LocalStack Azure emulator using the localstack CLI, execute the following command:

```bash
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>
IMAGE_NAME=localstack/localstack-azure-alpha localstack start
```

Navigate to the `scripts` folder:

```bash
cd samples/function-app-managed-identity/python/scripts
```

Make the script executable:

```bash
chmod +x deploy.sh
```

Run the deployment script:

```bash
./deploy.sh
```

## Validation

After deployment, you can use the `validate.sh` script to verify that all resources were created and configured correctly:

```bash
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

# Check function app status
$AZ functionapp show  \
  --name local-func-test \
  --resource-group local-rg \
  --output table

# Check storage account properties
$AZ storage account show \
  --name localstoragetest \
  --resource-group local-rg \
  --output table

# List storage containers
$AZ storage container list \
  --account-name localstoragetest \
  --output table \
  --only-show-errors
```

## Cleanup

To destroy all created resources:

```bash
# Delete resource group and all contained resources
az group delete --name local-rg --yes --no-wait

# Verify deletion
az group list --output table
```

This will remove all Azure resources created by the CLI deployment script.

## Related Documentation

- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)