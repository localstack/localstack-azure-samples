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
RESOURCE_GROUP_NAME="${PREFIX}-rg"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="S1"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
COSMOSDB_ACCOUNT_NAME="${PREFIX}-mongodb-${SUFFIX}"
MONGODB_DATABASE_NAME="sampledb"
COLLECTION_NAME="activities"
INDEXES='[{"key":{"keys":["username"]}},{"key":{"keys":["activity"]}},{"key":{"keys":["timestamp"]}}]'
SHARD="username"
THROUGHPUT=400
RUNTIME="python"
RUNTIME_VERSION="3.13"
LOGIN_NAME="Paolo"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Create a resource group
echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
az group create \
	--name $RESOURCE_GROUP_NAME \
	--location $LOCATION \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "Resource group [$RESOURCE_GROUP_NAME] created successfully."
else
	echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
	exit 1
fi

# Create a CosmosDB account with MongoDB kind
echo "Creating [$COSMOSDB_ACCOUNT_NAME] CosmosDB account in the [$RESOURCE_GROUP_NAME] resource group..."
az cosmosdb create \
	--name $COSMOSDB_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--locations regionName=$LOCATION \
	--kind MongoDB \
	--default-consistency-level Session \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "[$COSMOSDB_ACCOUNT_NAME] CosmosDB account successfully created in the [$RESOURCE_GROUP_NAME] resource group"
else
	echo "Failed to create [$COSMOSDB_ACCOUNT_NAME] CosmosDB account in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Retrieve document endpoint
DOCUMENT_ENDPOINT=$(az cosmosdb show \
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

# Create MongoDB database
echo "Creating [$MONGODB_DATABASE_NAME] MongoDB database in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account..."
az cosmosdb mongodb database create \
	--account-name $COSMOSDB_ACCOUNT_NAME \
	--name $MONGODB_DATABASE_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--output json \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "[$MONGODB_DATABASE_NAME] MongoDB database successfully created in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account"
else
	echo "Failed to create [$MONGODB_DATABASE_NAME] MongoDB database in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account"
	exit 1
fi

# Create a MongoDB database collection
echo "Creating [$COLLECTION_NAME] collection in the [$MONGODB_DATABASE_NAME] MongoDB database..."
az cosmosdb mongodb collection create \
	--account-name $COSMOSDB_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--database-name $MONGODB_DATABASE_NAME \
	--name $COLLECTION_NAME \
	--idx "$INDEXES" \
	--shard $SHARD \
	--throughput $THROUGHPUT \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "[$COLLECTION_NAME] collection successfully created in the [$MONGODB_DATABASE_NAME] MongoDB database"
else
	echo "Failed to create [$COLLECTION_NAME] collection in the [$MONGODB_DATABASE_NAME] MongoDB database"
	exit 1
fi

# List CosmosDB connection strings
echo "Listing connection strings for CosmosDB account [$COSMOSDB_ACCOUNT_NAME]..."
COSMOSDB_CONNECTION_STRING=$(azlocal cosmosdb keys list \
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

# Create App Service Plan
echo "Creating App Service Plan [$APP_SERVICE_PLAN_NAME]..."
az appservice plan create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_SERVICE_PLAN_NAME" \
	--location "$LOCATION" \
	--sku "$APP_SERVICE_PLAN_SKU" \
	--is-linux \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "App Service Plan [$APP_SERVICE_PLAN_NAME] created successfully."
else
	echo "Failed to create App Service Plan [$APP_SERVICE_PLAN_NAME]."
	exit 1
fi

# Create the web app
echo "Creating web app [$WEB_APP_NAME]..."
az webapp create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--plan "$APP_SERVICE_PLAN_NAME" \
	--name "$WEB_APP_NAME" \
	--runtime "$RUNTIME:$RUNTIME_VERSION" \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "Web app [$WEB_APP_NAME] created successfully."
else
	echo "Failed to create web app [$WEB_APP_NAME]."
	exit 1
fi

# Set web app settings
echo "Setting web app settings for [$WEB_APP_NAME]..."
az functionapp config appsettings set \
	--name $WEB_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	COSMOSDB_CONNECTION_STRING="$COSMOSDB_CONNECTION_STRING" \
	COSMOSDB_DATABASE_NAME="$MONGODB_DATABASE_NAME" \
	COSMOSDB_COLLECTION_NAME="$COLLECTION_NAME" \
	LOGIN_NAME="$LOGIN_NAME" \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "Web app settings for [$WEB_APP_NAME] set successfully."
else
	echo "Failed to set web app settings for [$WEB_APP_NAME]."
	exit 1
fi

# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py cosmosdb.py static templates requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using az webapp deploy command for LocalStack emulator environment."
	azlocal webapp deploy \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$WEB_APP_NAME" \
		--src-path "$ZIPFILE" \
		--type zip \
		--async true
else
	echo "Using standard az webapp deploy command for AzureCloud environment."
	az webapp deploy \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$WEB_APP_NAME" \
		--src-path "$ZIPFILE" \
		--type zip \
		--async true
fi

# Remove the zip package of the web app
rm "$ZIPFILE"
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

After deployment, validate that all resources were created and configured correctly:

1. Verify resource creation:

   ```bash
  # Check resource group
  azlocal group show \
  --name local-rg \
  --output table
  
  # List resources
  azlocal resource list \
  --resource-group local-rg \
  --output table
  
  # Check Azure Web App
  azlocal webapp show \
  --name local-webapp-test \
  --resource-group local-rg \
  --output table
   ```
2. Validate storage account:

   ```bash
  # Check Azure CosmosDB Account
  azlocal cosmosdb show \
  --name local-mongodb-test \
  --resource-group local-rg \
  --output table

  # Check MongoDB database
  azlocal cosmosdb mongodb database show \
  --name sampledb \
  --account-name local-mongodb-test \
  --resource-group local-rg \
  --output table

  # Check MongoDB collection
  azlocal cosmosdb mongodb collection show \
  --name activities \
  --database-name sampledb \
  --account-name local-mongodb-test \
  --resource-group local-rg \
  --output table
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