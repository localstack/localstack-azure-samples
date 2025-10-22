# Bicep Deployment

This directory contains the `main.bicep` Bicep module and `deploy.sh` deployment script for creating an Azure Functions application with supporting Azure services. The deployment creates a complete gaming scoreboard system using Azure Storage Account, App Service Plan, and Azure Functions with Infrastructure as Code (IaC) using Azure Bicep. For more information, see [Azure Functions Sample with LocalStack for Azure](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep): VS Code extension for Bicep language support and IntelliSense
- [.NET SDK](https://dotnet.microsoft.com/en-us/download): Required for building and publishing the C# Azure Functions application
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The deployment script uses the `azlocal` CLI instead of the standard Azure CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

The `deploy.sh` script creates the [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli) for all the Azure resources, while the `main.bicep` Bicep module creates the following Azure resources:

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob containers, queues, and tables for the gaming system
    - StorageV2 kind with Hot access tier
    - Provides blob containers, queues, and tables for the sample application
2. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): Hosting plan for the Azure Functions application
    - Linux-based hosting plan for containerized workloads
    - Standard sku
3. [Azure Linux Function App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview) Serverless compute platform hosting the gaming logic with consumption plan
    - Linux Function App with .NET isolated runtime
    - Comprehensive application settings for gaming system configuration

The system implements a complete gaming scoreboard with multiple Azure Functions that handle HTTP requests, process blob uploads, manage queue messages, and maintain game statistics. For more information, see [Azure Functions Sample with LocalStack for Azure](../README.md).

## Bicep Templates

The `main.bicep` Bicep template defines all Azure resources using declarative syntax:

```bicep
@description('Specifies the prefix for the name of the Azure resources.')
@minLength(2)
param prefix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the suffix for the name of the Azure resources.')
@minLength(2)
param suffix string = take(uniqueString(resourceGroup().id), 4)

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Specifies the sku of the Azure Storage account.')
param storageAccountSku string = 'Standard_LRS'

@description('Specifies the tier name for the hosting plan.')
@allowed([
  'Basic'
  'Standard'
  'ElasticPremium'
  'Premium'
  'PremiumV2'
  'Premium0V3'
  'PremiumV3'
  'PremiumMV3'
  'Isolated'
  'IsolatedV2'
  'WorkflowStandard'
  'FlexConsumption'
])
param skuTier string = 'Standard'

@description('Specifies the SKU name for the hosting plan.')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'EP1'
  'EP2'
  'EP3'
  'P1'
  'P2'
  'P3'
  'P1V2'
  'P2V2'
  'P3V2'
  'P0V3'
  'P1V3'
  'P2V3'
  'P3V3'
  'P1MV3'
  'P2MV3'
  'P3MV3'
  'P4MV3'
  'P5MV3'
  'I1'
  'I2'
  'I3'
  'I1V2'
  'I2V2'
  'I3V2'
  'I4V2'
  'I5V2'
  'I6V2'
  'WS1'
  'WS2'
  'WS3'
  'FC1'
])
param skuName string = 'S1'

@description('Specifies the kind of the hosting plan.')
@allowed([
  'app'
  'elastic'
  'functionapp'
  'windows'
  'linux'
])
param appServicePlanKind string = 'linux'

@description('Specifies whether the hosting plan is reserved.')
param reserved bool = true

@description('Specifies whether the hosting plan is zone redundant.')
param zoneRedundant bool = false

@description('Specifies the language runtime used by the Azure Functions App.')
@allowed([
  'dotnet'
  'dotnet-isolated'
  'python'
  'java'
  'node'
  'powerShell'
  'custom'
])
param runtimeName string

@description('Specifies the target language version used by the Azure Functions App.')
param runtimeVersion string

@description('Specifies the kind of the hosting plan.')
@allowed([
  'app'                                    // Windows Web app
  'app,linux'                              // Linux Web app
  'app,linux,container'                    // Linux Container Web app
  'hyperV'                                 // Windows Container Web App
  'app,container,windows'                  // Windows Container Web App
  'app,linux,kubernetes'                   // Linux Web App on ARC
  'app,linux,container,kubernetes'         // Linux Container Web App on ARC
  'functionapp'                            // Function Code App
  'functionapp,linux'                      // Linux Consumption Function app
  'functionapp,linux,container,kubernetes' // Function Container App on ARC
  'functionapp,linux,kubernetes'           // Function Code App on ARC
])
param functionAppKind string = 'functionapp,linux'

@description('Specifies whether HTTPS is enforced for the Azure Functions App.')
param httpsOnly bool = false

@description('Specifies the minimum TLS version for the Azure Functions App.')
@allowed([
  '1.0'
  '1.1'
  '1.2'
  '1.3'
])
param minTlsVersion string = '1.2'

@description('Specifies whether the public network access is enabled or disabled')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Optional Git Repo URL')
param repoUrl string = ' '

@description('Specifies the name of the input container.')
param inputContainerName string = 'input'

@description('Specifies the name of the output container.')
param outputContainerName string = 'output'

@description('Specifies the name of the input queue.')
param inputQueueName string = 'input'

@description('Specifies the name of the output queue.')
param outputQueueName string = 'output'

@description('Specifies the name of the trigger queue.')
param triggerQueueName string = 'trigger'

@description('Specifies the name of the input table.')
param inputTableName string = 'input'

@description('Specifies the name of the output table.')
param outputTableName string = 'output'

@description('Specifies the comma-separated list of player names.')
param playerNames string = 'Alice,Anastasia,Paolo,Leo,Mia'

@description('Specifies the timer schedule for the timer triggered function.')
param timerSchedule string = '0 */1 * * * *'

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

var functionAppName = '${prefix}-functionapp-${suffix}'
var appServicePlanPortalName = '${prefix}-app-service-plan-${suffix}'
var storageAccountName = '${prefix}storage${suffix}'
var storageAccountConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanPortalName
  location: location
  tags: tags
  kind: appServicePlanKind
  sku: {
    tier: skuTier
    name: skuName
  }
  properties: {
    reserved: reserved
    zoneRedundant: zoneRedundant
     maximumElasticWorkerCount: skuTier == 'FlexConsumption' ? 1 : 20
  }
}

resource functionApp 'Microsoft.Web/sites@2024-11-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: functionAppKind
  properties: {
    httpsOnly: httpsOnly
    reserved: true
    serverFarmId: appServicePlan.id
    virtualNetworkSubnetId: null
    siteConfig: {
      linuxFxVersion: toUpper('${runtimeName}|${runtimeVersion}')
      minTlsVersion: minTlsVersion
      ftpsState: 'FtpsOnly'
      publicNetworkAccess: publicNetworkAccess
    }
  }
  identity: {
    type: 'SystemAssigned'
  }

  resource configAppSettings 'config' = {
    name: 'appsettings'
    properties: {
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
      AzureWebJobsStorage: storageAccountConnectionString
	    WEBSITE_STORAGE_ACCOUNT_CONNECTION_STRING: storageAccountConnectionString
	    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: storageAccountConnectionString
      STORAGE_ACCOUNT_CONNECTION_STRING: storageAccountConnectionString
      INPUT_STORAGE_CONTAINER_NAME: inputContainerName
      OUTPUT_STORAGE_CONTAINER_NAME: outputContainerName
      INPUT_QUEUE_NAME: inputQueueName
      OUTPUT_QUEUE_NAME: outputQueueName
      TRIGGER_QUEUE_NAME: triggerQueueName
      INPUT_TABLE_NAME: inputTableName
      OUTPUT_TABLE_NAME: outputTableName
      PLAYER_NAMES: playerNames
      TIMER_SCHEDULE: timerSchedule
      FUNCTIONS_WORKER_RUNTIME: runtimeName
    }
  }
}

resource functionAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2024-11-01' = if (contains(repoUrl,'http')){
  name: 'web'
  parent: functionApp
  properties: {
    repoUrl: repoUrl
    branch: 'main'
    isManualIntegration: true
  }
}

output functionAppName string = functionAppName
output storageAccountName string = storageAccountName
output storageAccountConnectionString string = storageAccountConnectionString
output test1 string = storageAccount.properties.accessTier
output test2 string = functionApp.properties.enabledHostNames[0]
output test3 string = '${functionApp.kind} + ${appServicePlan.kind}'
output test4 string = split(functionApp.id, '/')[3]
```

## Deployment Script

Use the `deploy.sh` script to automate the provisioning of Azure resources and deployment of the Azure Functions App.

```bash
#!/bin/bash

# Start azure CLI local mode session
azlocal start_interception

# Variables
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
RESOURCE_GROUP_NAME="local-rg"
LOCATION="westeurope"
VALIDATE_TEMPLATE=1
USE_WHAT_IF=0
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

# Validates if the resource group exists in the subscription, if not creates it
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	# Create the resource group
	az group create --name $RESOURCE_GROUP_NAME --location $LOCATION 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created in the subscription [$SUBSCRIPTION_NAME]"
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]"
		exit
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists in the subscription [$SUBSCRIPTION_NAME]"
fi

# Validates the Bicep template
if [[ $VALIDATE_TEMPLATE == 1 ]]; then
	if [[ $USE_WHAT_IF == 1 ]]; then
		# Execute a deployment What-If operation at resource group scope.
		echo "Previewing changes deployed by Bicep template [$TEMPLATE]..."
		az deployment group what-if \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $TEMPLATE \
			--parameters $PARAMETERS \
			--parameters \
			location=$LOCATION

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			exit
		fi
	else
		# Validate the Bicep template
		echo "Validating Bicep template [$TEMPLATE]..."
		output=$(az deployment group validate \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $TEMPLATE \
			--parameters $PARAMETERS \
			--parameters \
			location=$LOCATION)

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			echo "$output"
			exit
		fi
	fi
fi

# Deploy the Bicep template
echo "Deploying Bicep template [$TEMPLATE]..."
if DEPLOYMENT_OUTPUTS=$(az deployment group create \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors \
	--template-file $TEMPLATE \
	--parameters $PARAMETERS \
	--parameters location=$LOCATION \
	--query 'properties.outputs' -o json); then
	echo "Bicep template [$TEMPLATE] deployed successfully. Outputs:"
	echo "$DEPLOYMENT_OUTPUTS" | jq .
	FUNCTION_APP_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.functionAppName.value')
	STORAGE_ACCOUNT_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.storageAccountName.value')
	STORAGE_ACCOUNT_CONNECTION_STRING=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.storageAccountConnectionString.value')
	echo "Function App Name: $FUNCTION_APP_NAME"
	echo "Storage Account Name: $STORAGE_ACCOUNT_NAME"
	echo "Storage Account Connection String: $STORAGE_ACCOUNT_CONNECTION_STRING"
else
	echo "Failed to deploy Bicep template [$TEMPLATE]"
	exit 1
fi

if [[ -z "$FUNCTION_APP_NAME" || -z "$STORAGE_ACCOUNT_NAME" ]]; then
	echo "Function App Name or Storage Account Name is empty. Exiting."
	exit 1
fi

# Print the application settings of the function app
echo "Retrieving application settings for function app [$FUNCTION_APP_NAME]..."
az webapp config appsettings list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME"

# CD into the function app directory
cd ../src/sample || exit

# Clean and build the project in Release configuration
dotnet clean
dotnet build -c Release

# Publish the project to a publish directory
dotnet publish -c Release -o publish

# Create deployment zip from the published output
cd publish || exit
zip -r ../azure-function-deployment.zip .
cd .. || exit

# Deploy the function app using the zip file
echo "Deploying function app [$FUNCTION_APP_NAME]..."
azlocal functionapp deploy \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$FUNCTION_APP_NAME" \
    --src-path ./azure-function-deployment.zip \
    --type zip

# Stop azure CLI local mode session
azlocal stop_interception
```

> **Note**  
> You can use the `azlocal` CLI as a drop-in replacement for the `az` CLI to direct all commands to the LocalStack for Azure emulator. Alternatively, run `azlocal start_interception` to automatically intercept and redirect all `az` commands to LocalStack. For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

The `deploy.sh` script executes the following steps:

- Specifies the variables used during deployment.
- Creates the resource group if it does not exist.
- Conditionally validates the `main.bicep` module to check its syntax is correct and all parameters make sense.
- Conditionally runs a what-if deployment to execute a dry run to preview the resources that will be created, updated, or deleted.
- Runs the `main.bicep` template to create all the Azure resources.
- Collects important information from the deployment (like resource names) for later use.
- Uses jq (a JSON tool) to extract the names of resources we just created.
- Shows us all the settings that got applied to the Function App.
- Removes previous build artifacts for consistency.
- Creates self-contained deployment with all dependencies.
- Creates zip archive in format expected by Azure Functions.
- Uploads pre-built application package to the newly created Azure Functions app.

> **Note**  
> Azure CLI commands supports `--verbose` argument to print execution details and the `--debug` flag to show low-level REST calls for debugging. For more information, see [Get started with Azure CLI](https://learn.microsoft.com/en-us/cli/azure/get-started-with-azure-cli)

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
   cd samples/function-app-and-storage/dotnet/bicep
   ```

4. Make the script executable:

   ```bash
   chmod +x deploy.sh
   ```

5. Run the deployment script:

   ```bash
   ./deploy.sh
   ```

## Validation

After deployment, validate that all resources were created and configured correctly:

1. Verify resource creation:

   ```bash
  # Check resource group
  azlocal group show --name local-rg --output table
  
  # List resources
  azlocal resource list --resource-group local-rg --output table
  
  # Check function app status
  azlocal functionapp show --name local-func-test --resource-group local-rg --output table
   ```
2. Validate storage account:

   ```bash
  # Check storage account properties
  azlocal storage account show --name localstoragetest --resource-group local-rg --output table

  # List storage containers
  azlocal storage container list --account-name localstoragetest --output table --only-show-errors

  # List storage queues
  azlocal storage queue list --account-name localstoragetest --output table --only-show-errors
  
  # List storage tables
  azlocal storage table list --account-name localstoragetest --output table --only-show-errors
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

- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Bicep Language Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)
- [Azure Functions Methods Documentation](../src/sample/Methods.md) - Detailed documentation of all implemented functions