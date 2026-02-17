# Bicep Deployment

This directory contains the Bicep template and a deployment script for provisioning Azure services in LocalStack for Azure. For further details about the sample application, refer to the [Azure Web App with Azure CosmosDB for MongoDB](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep): VS Code extension for Bicep language support and IntelliSense
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [Azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [Python](https://www.python.org/downloads/): Python runtime (version 3.12 or above)
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The [deploy.sh](deploy.sh) Bash script uses the `azlocal` CLI instead of the standard Azure CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

The [deploy.sh](deploy.sh) script creates the [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli) for all the Azure resources, while the [main.bicep](main.bicep) Bicep module creates the following Azure resources:

1. [Azure CosmosDB Account (MongoDB API)](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/introduction): A globally distributed database account configured for MongoDB workloads, with multi-region failover.
2. [MongoDB Database](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/overview): The `sampledb` database for storing application data.
3. [MongoDB Collection](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/overview): The `activities` collection within `sampledb` for storing vacation activity records.
4. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): The compute resource that hosts the web application.
5. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): Hosts the Python Flask single-page application (*Vacation Planner*), connected to CosmosDB for MongoDB.
6. [App Service Source Control](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/create-or-update-source-control?view=rest-appservice-2024-11-01): (Optional) Configures automatic deployment from a public GitHub repository.

The web app allows users to plan and manage vacation activities, storing all activity data in a MongoDB collection. 

## Configuration

Before deploying the `main.bicep` template, update the `bicep.bicepparam` file with your specific values:

```bicep
using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param runtimeName = 'python'
param runtimeVersion = '3.13'
param databaseName = 'sampledb'
param collectionName = 'activities'
param username = 'paolo'
param primaryRegion = 'westeurope'
param secondaryRegion = 'northeurope'
```

## Provisioning Scripts

See [deploy.sh](deploy.sh) for the complete deployment automation. The script performs:

- Detects environment (LocalStack vs Azure Cloud) and uses appropriate CLI
- Creates resource group if it doesn't exist
- Optionally validates the Bicep template
- Optionally runs what-if deployment for preview
- Deploys the main.bicep template with parameters from [main.bicepparam](main.bicepparam)
- Extracts deployment outputs (Web App name, CosmosDB details)
- Creates zip package of the Python application
- Deploys the zip to Azure Web App

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
cd samples/web-app-cosmosdb-mongodb-api/python/bicep
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

# Check Azure Web App
$AZ webapp show \
--name local-webapp-test \
--resource-group local-rg \
--output table

# Check Azure CosmosDB account
$AZ cosmosdb show \
--name local-mongodb-test \
--resource-group local-rg \
--output table

# Check MongoDB database
$AZ cosmosdb mongodb database show \
--name sampledb \
--account-name local-mongodb-test \
--resource-group local-rg \
--output table

# Check MongoDB collection
$AZ cosmosdb mongodb collection show \
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

- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Bicep Language Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)