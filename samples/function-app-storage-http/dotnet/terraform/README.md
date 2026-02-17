# Terraform Deployment

This directory contains Terraform modules and `deploy.sh` deployment script for creating Azure services. For more information, see [Azure Functions Sample with LocalStack for Azure](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Terraform](https://developer.hashicorp.com/terraform/downloads): Infrastructure as Code tool for provisioning Azure resources
- [.NET SDK](https://dotnet.microsoft.com/en-us/download): Required for building and publishing the C# Azure Functions application
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The [deploy.sh](deploy.sh) script uses the `azlocal` CLI instead of the standard Azure CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

The [main.tf](main.tf) Terraform module creates the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all gaming system resources
2. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob containers, queues, and tables for the gaming system
3. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): Hosting plan for the Azure Functions application
4. [Azure Linux Function App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview) Serverless compute platform hosting the gaming logic with consumption plan

The system implements a complete gaming scoreboard with multiple Azure Functions that handle HTTP requests, process blob uploads, manage queue messages, and maintain game statistics.

## Provisioning Scripts

See [deploy.sh](deploy.sh) for the complete deployment automation. The script performs:

- Detects environment (LocalStack vs Azure Cloud) and uses appropriate CLI (`tflocal`/`azlocal` or `terraform`/`az`)
- Initializes Terraform and downloads required providers
- Creates and validates Terraform execution plan with custom variables
- Applies Terraform configuration to provision Azure resources
- Extracts output values (resource group name, function app name)
- Builds and publishes the .NET application in Release configuration
- Creates deployment zip package from published output
- Deploys the zip to Azure Function App using Azure CLI

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
   cd samples/function-app-and-storage/dotnet/terraform
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

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)
- [Azure Functions Methods Documentation](../src/sample/Methods.md) - Detailed documentation of all implemented functions