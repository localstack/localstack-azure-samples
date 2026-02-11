# Azure CLI Deployment

This folder contains Bash scripts for deploying an Azure Functions application with supporting Azure services using the `azlocal` CLI. The deployment creates a complete gaming scoreboard system using Azure Functions and Azure Storage Account with direct Azure CLI commands through the LocalStack Azure emulator. For more information, see [Azure Functions Sample with LocalStack for Azure](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [.NET SDK](https://dotnet.microsoft.com/en-us/download): Required for building and publishing the C# Azure Functions application
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [funclocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Functions Core Tools wrapper
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The deployment script uses the `azlocal` CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

This CLI deployment creates the following Azure resources using direct Azure CLI commands:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all gaming system resources
2. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob containers, queues, and tables for the gaming system
3. [Azure Linux Function App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview) Serverless compute platform hosting the gaming logic with consumption plan

The system implements a complete gaming scoreboard with multiple Azure Functions that handle HTTP requests, process blob uploads, manage queue messages, and maintain game statistics. For more information, see [Azure Functions Sample with LocalStack for Azure](../README.md).

## Deployment Script 

The [deploy.sh](deploy.sh) script creates resources and deploys the .NET application using native Azure CLI command. 

```bash
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

# Publish the function app
echo "Publishing function app [$FUNCTION_APP_NAME]..."
$FUNC azure functionapp publish $FUNCTION_APP_NAME --dotnet-isolated --verbose --debug
```

> [!NOTE]
> You can use the `azlocal` CLI as a drop-in replacement for the `az` CLI to direct all commands to the LocalStack for Azure emulator. Alternatively, run `azlocal start_interception` to automatically intercept and redirect all `az` commands to LocalStack. To revert back to the default behavior and send commands to the Azure cloud, run `azlocal stop_interception`.


## Deployment

1. You can set up the Azure emulator by utilizing LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/?__hstc=108988063.8aad2b1a7229945859f4d9b9bb71e05d.1743148429561.1758793541854.1758810151462.32&__hssc=108988063.3.1758810151462&__hsfp=3945774529) to obtain your Auth Token and specify it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure-alpha). To pull the Azure Docker image, execute the following command:

   ```bash
   docker pull localstack/localstack-azure-alpha
   ```

2. Start the LocalStack Azure emulator using the localstack CLI, execute the following command:

   ```bash
   export LOCALSTACK_AUTH_TOKEN=<your_auth_token>
   IMAGE_NAME=localstack/localstack-azure-alpha localstack start
   ```

3. Navigate to the scripts directory

   ```bash
   cd samples/function-app-and-storage/dotnet/scripts
   ```

4. Make the script executable:

   ```bash
   chmod +x deploy.sh
   ```

5. Run the deployment script:

   ```bash
   ./deploy.sh
   ```

## Configuration Options

### Environment Variables

You can customize the deployment by modifying the variables at the top of `deploy.sh`:

```bash
# Customizable variables
PREFIX='myapp'              # Change resource name prefix
SUFFIX='prod'               # Change resource name suffix  
LOCATION='eastus'           # Change deployment region
RUNTIME="DOTNET-ISOLATED"   # Runtime type
RUNTIME_VERSION="9"         # Runtime version
```

### Application Settings

The script configures the following application settings for the gaming system:

| Setting | Purpose | Default Value |
|---------|---------|---------------|
| `AzureWebJobsStorage` | Functions runtime storage | Auto-generated connection string |
| `STORAGE_ACCOUNT_CONNECTION_STRING` | Application storage access | Auto-generated connection string |
| `INPUT_STORAGE_CONTAINER_NAME` | Blob input container | `input` |
| `OUTPUT_STORAGE_CONTAINER_NAME` | Blob output container | `output` |
| `INPUT_QUEUE_NAME` | Message input queue | `input` |
| `OUTPUT_QUEUE_NAME` | Message output queue | `output` |
| `TRIGGER_QUEUE_NAME` | Queue trigger name | `trigger` |
| `INPUT_TABLE_NAME` | Scoreboards table | `scoreboards` |
| `OUTPUT_TABLE_NAME` | Winners table | `winners` |
| `PLAYER_NAMES` | Game player list | Comma-separated names |
| `TIMER_SCHEDULE` | Scheduled function trigger | `0 */1 * * * *` (every minute) |
| `FUNCTIONS_WORKER_RUNTIME` | Runtime specification | `dotnet-isolated` |

### LocalStack-Specific Commands

1. `azlocal start_interception`:
   - Redirects Azure CLI calls to LocalStack endpoints
   - Enables local development without Azure subscription
   - Maintains compatibility with standard Azure CLI syntax

2. `funclocal azure functionapp publish`:
   - Deploys function app to LocalStack Azure emulator
   - Wraps the Azure Functions Core Tools
   - Provides local testing environment for Azure Functions

3. `azlocal stop_interception`:
   - Restores normal Azure CLI behavior
   - Cleans up LocalStack session state
   - Returns CLI to standard Azure cloud operations

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

# List storage queues
$AZ storage queue list \
  --account-name localstoragetest \
  --output table \
  --only-show-errors

# List storage tables
$AZ storage table list \
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
- [Azure Functions CLI Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local)
- [Azure Functions Methods Documentation](../src/sample/Methods.md) - Detailed documentation of all implemented functions
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)
