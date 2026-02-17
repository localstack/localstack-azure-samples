# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning Azure services in LocalStack for Azure. For further details about the sample application, refer to the [Azure Web App with Azure CosmosDB for MongoDB](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Terraform](https://developer.hashicorp.com/terraform/downloads): Infrastructure as Code tool for provisioning Azure resources
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

The [main.tf](main.tf) Terraform module creates the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all resources in the sample.
2. [Azure CosmosDB Account (MongoDB API)](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/introduction): A globally distributed database account configured for MongoDB workloads, with multi-region failover.
3. [MongoDB Database](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/overview): The `sampledb` database for storing application data.
4. [MongoDB Collection](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/overview): The `activities` collection within `sampledb` for storing vacation activity records.
5. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): The compute resource that hosts the web application.
6. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): Hosts the Python Flask single-page application (*Vacation Planner*), connected to CosmosDB for MongoDB.
7. [App Service Source Control](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/create-or-update-source-control?view=rest-appservice-2024-11-01): (Optional) Configures automatic deployment from a public GitHub repository.

The web app allows users to plan and manage vacation activities, storing all activity data in the CosmosDB-backed MongoDB collection. All resources are provisioned and configured using Terraform for easy reproducibility and local development with LocalStack for Azure.

## Provisioning Scripts

You can use the [deploy.sh](deploy.sh) script to automate the deployment of all Azure resources and the sample application in a single step, streamlining setup and reducing manual configuration. The script executes the following steps:

- Cleans up any previous Terraform state and plan files to ensure a fresh deployment.
- Initializes the Terraform working directory and downloads required plugins.
- Creates and validates a Terraform execution plan for the Azure infrastructure.
- Applies the Terraform plan to provision all necessary Azure resources.
- Extracts resource names and outputs from the Terraform deployment.
- Packages the code of the web application into a zip file for deployment.
- Deploys the zip package to the Azure Web App using the LocalStack Azure CLI.

## Configuration

When using LocalStack for Azure, configure the `metadata_host` and `subscription_id` settings in the [Azure Provider for Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) to ensure proper connectivity:


```hcl
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  # Set the hostname of the Azure Metadata Service (for example management.azure.com) 
  # used to obtain the Cloud Environment when using LocalStack's Azure emulator. 
  # This allows the provider to correctly identify the environment and avoid making calls to the real Azure endpoints. 
  metadata_host="localhost.localstack.cloud:4566"

  # Set the subscription ID to a dummy value when using LocalStack's Azure emulator.
  subscription_id = "00000000-0000-0000-0000-000000000000"
}
```

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

Navigate to the `terraform` folder:

```bash
cd samples/web-app-cosmosdb-mongodb-api/python/terraform
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

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)