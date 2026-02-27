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

The [deploy.sh](deploy.sh) script creates the [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli) for all the Azure resources, while the Bicep modules create the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): A logical container scoping all resources in this sample.
2. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview): Hosts two subnets:
	- *app-subnet*: Dedicated to [regional VNet integration](https://learn.microsoft.com/azure/azure-functions/functions-networking-options?tabs=azure-portal#outbound-networking-features) with the Function App.
	- *pe-subnet*: Used for hosting Azure Private Endpoints.
3. [Azure Private DNS Zone](https://learn.microsoft.com/azure/dns/private-dns-privatednszone): Handles DNS resolution for the CosmosDB for MongoDB Private Endpoint within the virtual network.
4. [Azure Private Endpoint](https://learn.microsoft.com/azure/private-link/private-endpoint-overview): Secures network access to the CosmosDB for MongoDB account via a private IP within the VNet.
5. [Azure NAT Gateway](https://learn.microsoft.com/azure/nat-gateway/nat-overview): Provides deterministic outbound connectivity for the Web App. Included for completeness; the sample app does not call any external services.
6. [Azure Network Security Group](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview): Enforces inbound and outbound traffic rules across the virtual network's subnets.
7. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview): Centralizes diagnostic logs and metrics from all resources in the solution.
8. [Azure Cosmos DB for MongoDB](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/introduction): A globally distributed database account optimized for MongoDB workloads, with multi-region failover enabled.
9. [MongoDB Database](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/overview): The `sampledb` database that holds all application data.
10. [MongoDB Collection](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/overview): The `activities` collection within `sampledb`, used to store vacation activity records.
11. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): The underlying compute tier that hosts the web application.
12. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): Runs the Python Flask single-page application (*Vacation Planner*), connected to CosmosDB for MongoDB via VNet integration.
13. [App Service Source Control](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/create-or-update-source-control?view=rest-appservice-2024-11-01): *(Optional)* Configures continuous deployment from a public GitHub repository.

The web app enables users to plan and manage vacation activities, with all data persisted in a CosmosDB-backed MongoDB collection. For more information on the sample application, see [Azure Web App with Azure CosmosDB for MongoDB](../README.md). 

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

Once the deployment completes, run the [validate.sh](../scripts/validate.sh) script to confirm that all resources were provisioned and configured as expected:

```bash
#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
WEBAPP_SUBNET_NSG_NAME="${PREFIX}-webapp-subnet-nsg-${SUFFIX}"
PE_SUBNET_NSG_NAME="${PREFIX}-pe-subnet-nsg-${SUFFIX}"
NAT_GATEWAY_NAME="${PREFIX}-nat-gateway-${SUFFIX}"
VIRTUAL_NETWORK_NAME="${PREFIX}-vnet-${SUFFIX}"
PRIVATE_DNS_ZONE_NAME="privatelink.mongo.cosmos.azure.com"
PRIVATE_ENDPOINT_NAME="${PREFIX}-mongodb-pe-${SUFFIX}"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
WEBAPP_NAME="${PREFIX}-webapp-${SUFFIX}"
COSMOSDB_ACCOUNT_NAME="${PREFIX}-mongodb-${SUFFIX}"
MONGODB_DATABASE_NAME="sampledb"
COLLECTION_NAME="activities"
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
echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
$AZ group show \
	--name "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check App Service Plan
echo -e "\n[$APP_SERVICE_PLAN_NAME] app service plan:\n"
$AZ appservice plan show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_SERVICE_PLAN_NAME" \
	--output table \
	--only-show-errors

# Check Azure Web App
echo -e "\n[$WEBAPP_NAME] web app:\n"
$AZ webapp show \
	--name "$WEBAPP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Azure CosmosDB account
echo -e "\n[$COSMOSDB_ACCOUNT_NAME] cosmosdb account:\n"
$AZ cosmosdb show \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,DocumentEndpoint:documentEndpoint}' \
	--output table \
	--only-show-errors

# Check MongoDB database
echo -e "\n[$MONGODB_DATABASE_NAME] mongodb database:\n"
$AZ cosmosdb mongodb database show \
	--name "$MONGODB_DATABASE_NAME" \
	--account-name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,ResourceGroup:resourceGroup}' \
	--output table \
	--only-show-errors

# Check MongoDB collection
echo -e "\n[$COLLECTION_NAME] mongodb collection:\n"
$AZ cosmosdb mongodb collection show \
	--name "$COLLECTION_NAME" \
	--database-name "$MONGODB_DATABASE_NAME" \
	--account-name "$COSMOSDB_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Log Analytics Workspace
echo -e "\n[$LOG_ANALYTICS_NAME] log analytics workspace:\n"
$AZ monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup}' \
	--output table \
	--only-show-errors

# Check NAT Gateway
echo -e "\n[$NAT_GATEWAY_NAME] nat gateway:\n"
$AZ network nat gateway show \
	--name "$NAT_GATEWAY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Virtual Network
echo -e "\n[$VIRTUAL_NETWORK_NAME] virtual network:\n"
$AZ network vnet show \
	--name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Private DNS Zone
echo -e "\n[$PRIVATE_DNS_ZONE_NAME] private dns zone:\n"
$AZ network private-dns zone show \
	--name "$PRIVATE_DNS_ZONE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,ResourceGroup:resourceGroup,RecordSets:recordSets,VirtualNetworkLinks:virtualNetworkLinks}' \
	--output table \
	--only-show-errors

# Check Private Endpoint
echo -e "\n[$PRIVATE_ENDPOINT_NAME] private endpoint:\n"
$AZ network private-endpoint show \
	--name "$PRIVATE_ENDPOINT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Web App Subnet NSG
echo -e "\n[$WEBAPP_SUBNET_NSG_NAME] network security group:\n"
$AZ network nsg show \
	--name "$WEBAPP_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Private Endpoint Subnet NSG
echo -e "\n[$PE_SUBNET_NSG_NAME] network security group:\n"
$AZ network nsg show \
	--name "$PE_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# List resources
echo -e "\n[$RESOURCE_GROUP_NAME] all resources:\n"
$AZ resource list \
	--resource-group "$RESOURCE_GROUP_NAME" \
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