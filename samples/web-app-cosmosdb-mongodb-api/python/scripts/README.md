# Azure CLI Deployment

This directory includes Bash scripts designed for deploying and testing the sample Web App utilizing the `azlocal` CLI. For further details about the sample application, refer to the [Azure Web App with Azure CosmosDB for MongoDB](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [Azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [Python](https://www.python.org/downloads/): Python runtime (version 3.12 or above)
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The [deploy.sh](deploy.sh) Bash script uses the `azlocal` CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

This [deploy.sh](deploy.sh) script creates the following Azure resources using Azure CLI commands:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all gaming system resources.
2. [Azure CosmosDB Account (MongoDB API)](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/introduction): A globally distributed database account configured for MongoDB workloads, with multi-region failover.
3. [MongoDB Database](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/overview): The `sampledb` database for storing application data.
4. [MongoDB Collection](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/overview): The `activities` collection within `sampledb` for storing vacation activity records.
5. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): The compute resource that hosts the web application.
6. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): Hosts the Python Flask single-page application (*Vacation Planner*), connected to CosmosDB for MongoDB.
7. [App Service Source Control](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/create-or-update-source-control?view=rest-appservice-2024-11-01): (Optional) Configures automatic deployment from a public GitHub repository.

The web app allows users to plan and manage vacation activities, storing all activity data in a MongoDB collection. For more information on the sample application, see [Azure Web App with Azure CosmosDB for MongoDB](../README.md).

## Provisioning Scripts 

See [deploy.sh](deploy.sh) for the complete deployment script. The script performs:

- Detects environment (LocalStack vs Azure Cloud) and uses appropriate CLI
- Creates resource group
- Creates CosmosDB account with MongoDB kind (API version 7.0)
- Retrieves document endpoint
- Creates MongoDB database and collection with indexes and sharding
- Retrieves CosmosDB connection string
- Creates App Service Plan (Linux)
- Creates Web App with Python runtime
- Configures Web App settings (CosmosDB connection, database/collection names)
- Creates zip package of the application
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

Navigate to the `scripts` folder:

```bash
cd samples/web-app-cosmosdb-mongodb-api/python/scripts
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

- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)