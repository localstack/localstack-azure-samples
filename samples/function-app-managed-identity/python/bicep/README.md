# Bicep Deployment

This directory contains the Bicep template and a deployment script for provisioning Azure services in LocalStack for Azure. Refer to the [Azure Functions App with Managed Identity](../README.md) guide for details about the sample application.

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep): VS Code extension for Bicep language support and IntelliSense
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [Python](https://www.python.org/downloads/): Python runtime (version 3.13 or above)
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The deployment script uses the `azlocal` CLI instead of the standard Azure CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

The Bicep template deploys the following Azure resources:

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage with `input` and `output` containers for storing text blobs processed by the function app.
2. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): Defines the compute resources (CPU, memory, and scaling options) that host the Azure Functions app.
3. [Azure Functions App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview): Hosts the serverless application that processes text blobs. The function app uses managed identity to securely access the Azure Storage Account without requiring explicit credentials.
4. [Managed Identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview): Provides secure, credential-free authentication between the Azure Functions app and storage account. Supports both system-assigned and user-assigned identity types.
5. [Role Assignment](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments): Grants the Azure Functions app's managed identity the Storage Blob Data Contributor and Storage Queue Data Contributor roles, enabling read/write access to blob containers and queues for processing text data.

For more information on the sample application, see [Azure Functions App with Managed Identity](../README.md).

## Bicep Templates

The `main.bicep` Bicep template defines all Azure resources using declarative syntax. The module uses conditional provisioning for the user-assigned managed identity and role assignments resources. In Bicep, you can conditionally deploy a resource by passing in a parameter that specifies if the resource is deployed. Test the condition with an if expression in the resource declaration. For more information, see [Conditional deployments in Bicep with the if expression](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/conditional-resource-deployment).

```bicep
@description('Specifies the prefix for the name of the Azure resources.')
@minLength(2)
param prefix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the suffix for the name of the Azure resources.')
@minLength(2)
param suffix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

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

@description('Specifies whether Always On is enabled for the Azure Functions App.')
param alwaysOn bool = true

@description('Specifies the optional Git Repo URL.')
param repoUrl string = ''

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

@description('Specifies the sku of the Azure Storage account.')
param storageAccountSku string = 'Standard_LRS'

@description('Specifies the name of the input container.')
param inputContainerName string = 'input'

@description('Specifies the name of the output container.')
param outputContainerName string = 'output'

@description('Specifies the type of managed identity.')
@allowed([
  'SystemAssigned'
  'UserAssigned'
])
param managedIdentityType string = 'SystemAssigned'

var functionAppName = '${prefix}-functionapp-${suffix}'
var appServicePlanName = '${prefix}-app-service-plan-${suffix}'
var storageAccountName = '${prefix}storage${suffix}'
var managedIdentityName = '${prefix}-identity-${suffix}'
var storageAccountConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (managedIdentityType == 'UserAssigned') {
  name: managedIdentityName
  location: location
  tags: tags
}

resource storageBlobDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  scope: subscription()
}

resource storageQueueDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  scope: subscription()
}

resource storageBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageBlobDataContributorRoleDefinition.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleDefinition.id
    principalId: managedIdentityType == 'SystemAssigned' ? functionApp.identity.principalId : managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageQueueDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageQueueDataContributorRoleDefinition.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageQueueDataContributorRoleDefinition.id
    principalId: managedIdentityType == 'SystemAssigned' ? functionApp.identity.principalId : managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

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

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource inputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  parent: blobServices
  name: inputContainerName
}

resource outputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  parent: blobServices
  name: outputContainerName
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanName
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
      alwaysOn: alwaysOn
      linuxFxVersion: toUpper('${runtimeName}|${runtimeVersion}')
      minTlsVersion: minTlsVersion
      ftpsState: 'FtpsOnly'
      publicNetworkAccess: publicNetworkAccess
    }
  }
  identity: {
    type: managedIdentityType
    userAssignedIdentities  : managedIdentityType == 'SystemAssigned' ? null : {
      '${managedIdentity.id}': {}
    } 
  }
}

resource configAppSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    ENABLE_ORYX_BUILD: 'true'
    AzureWebJobsStorage: storageAccountConnectionString
    FUNCTIONS_WORKER_RUNTIME: runtimeName
    FUNCTIONS_EXTENSION_VERSION: '~4'
    STORAGE_ACCOUNT_CONNECTION_STRING__blobServiceUri: storageAccount.properties.primaryEndpoints.blob
    STORAGE_ACCOUNT_CONNECTION_STRING__queueServiceUri: storageAccount.properties.primaryEndpoints.queue
    STORAGE_ACCOUNT_CONNECTION_STRING__tableServiceUri: storageAccount.properties.primaryEndpoints.table
    INPUT_STORAGE_CONTAINER_NAME: inputContainer.name
	  OUTPUT_STORAGE_CONTAINER_NAME: outputContainer.name
    AZURE_CLIENT_ID: managedIdentityType == 'SystemAssigned' ? '' : managedIdentity.properties.clientId
  }
  dependsOn: [
    storageBlobDataContributorRoleAssignment
  ]
}

resource functionAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2024-11-01' = if (contains(repoUrl,'http')){
  name: 'web'
  parent: functionApp
  properties: {
    repoUrl: repoUrl
    branch: 'master'
    isManualIntegration: true
  }
}

output appServicePlanName string = appServicePlan.name
output functionAppName string = functionApp.name
output functionAppUrl string = functionApp.properties.defaultHostName
output storageAccountName string = storageAccountName
```
## Configuration

Before deploying the `main.bicep` template, update the `bicep.bicepparam` file with your specific values. Note that the `deploy.sh` script overrides some of these parameters.

```bicep
using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param runtimeName = 'python'
param runtimeVersion = '3.13'
```

## Deployment Script

You can use the `deploy.sh` script to automate the deployment of all Azure resources and the sample application in a single step, streamlining setup and reducing manual configuration. Before running the script, customize the variable values based on your needs. In particular, use the `MANAGED_IDENTITY_TYPE` variable to specify the type of managed identity to provision: `SystemAssigned` or `UserAssigned`.

```bash
#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
RESOURCE_GROUP_NAME="$PREFIX-rg"
LOCATION="westeurope"
MANAGED_IDENTITY_TYPE='UserAssigned' # SystemAssigned or UserAssigned
VALIDATE_TEMPLATE=1
USE_WHAT_IF=0
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="function_app.zip"
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

# Validates if the resource group exists in the subscription, if not creates it
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

# Validates the Bicep template
if [[ $VALIDATE_TEMPLATE == 1 ]]; then
	if [[ $USE_WHAT_IF == 1 ]]; then
		# Execute a deployment What-If operation at resource group scope.
		echo "Previewing changes deployed by Bicep template [$TEMPLATE]..."
		$AZ deployment group what-if \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $TEMPLATE \
			--parameters $PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			managedIdentityType=$MANAGED_IDENTITY_TYPE \
			--only-show-errors

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			exit
		fi
	else
		# Validate the Bicep template
		echo "Validating Bicep template [$TEMPLATE]..."
		output=$($AZ deployment group validate \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $TEMPLATE \
			--parameters $PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			managedIdentityType=$MANAGED_IDENTITY_TYPE \
			--only-show-errors)

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
if DEPLOYMENT_OUTPUTS=$($AZ deployment group create \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors \
	--template-file $TEMPLATE \
	--parameters $PARAMETERS \
	--parameters location=$LOCATION \
	prefix=$PREFIX \
	suffix=$SUFFIX \
	managedIdentityType=$MANAGED_IDENTITY_TYPE \
	--query 'properties.outputs' -o json); then
	echo "Bicep template [$TEMPLATE] deployed successfully. Outputs:"
	echo "$DEPLOYMENT_OUTPUTS" | jq .
	APP_SERVICE_PLAN_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.appServicePlanName.value')
	FUNCTION_APP_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.functionAppName.value')
	FUNCTION_APP_URL=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.functionAppUrl.value')
	STORAGE_ACCOUNT_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.storageAccountName.value')
	echo "Deployment details:"
	echo "- appServicePlanName: $APP_SERVICE_PLAN_NAME"
	echo "- functionAppName: $FUNCTION_APP_NAME"
	echo "- functionAppUrl: $FUNCTION_APP_URL"
	echo "- storageAccountName: $STORAGE_ACCOUNT_NAME"
else
	echo "Failed to deploy Bicep template [$TEMPLATE]"
	exit 1
fi

# Validation before deploying the function app
if [[ -z "$FUNCTION_APP_NAME" ]]; then
	echo "Function App Name is empty. Exiting."
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
- Creates zip archive in format expected by Function App.
- Uploads pre-built application package to the newly created Function App.

> **Note**  
> Azure CLI commands use `--verbose` argument to print execution details and the `--debug` flag to show low-level REST calls for debugging. For more information, see [Get started with Azure CLI](https://learn.microsoft.com/en-us/cli/azure/get-started-with-azure-cli)

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

Navigate to the `bicep` folder:

```bash
cd samples/function-app-managed-identity/python/bicep
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

- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Bicep Language Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)