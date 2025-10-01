# Azure Functions Terraform Deployment

This directory contains Terraform modules and `deploy.sh` deployment script for creating an Azure Functions application with supporting Azure services. The deployment creates a complete gaming scoreboard system using Azure Storage Account, App Service Plan, and Azure Functions. For more information, see [Azure Functions Sample with LocalStack for Azure](../README.md).

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

The deployment script uses the `azlocal` CLI instead of the standard Azure CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

This Terraform deployment creates the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all gaming system resources
2. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob containers, queues, and tables for the gaming system
3. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): Hosting plan for the Azure Functions application
4. [Azure Linux Function App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview) Serverless compute platform hosting the gaming logic with consumption plan

The system implements a complete gaming scoreboard with multiple Azure Functions that handle HTTP requests, process blob uploads, manage queue messages, and maintain game statistics.

## Terraform Modules

Below is a summary of the key Terraform modules included in this deployment:

- **`main.tf`**: Defines all Azure resources and their configuration.
- **`variables.tf`**: Declares input variables and validation rules.
- **`outputs.tf`**: Specifies output values after deployment.
- **`providers.tf`**: Configures the Terraform provider for Azure.

Below you can read the declarative code in HashiCorp Configuration Language (HCL):

```terraform
# Local Variables
locals {
  storage_account_name  = "${var.prefix}storage${var.suffix}"
  app_service_plan_name = "${var.prefix}-app-service-plan-${var.suffix}"
  function_app_name     = "${var.prefix}-functionapp-${var.suffix}"
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  location = var.location
  name     = var.resource_group_name
  tags     = var.tags
}

# Create a storage account
resource "azurerm_storage_account" "example" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_replication_type = var.account_replication_type
  account_kind             = var.account_kind
  account_tier             = var.account_tier
  tags                     = var.tags

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Create a service plan
resource "azurerm_service_plan" "example" {
  name                   = local.app_service_plan_name
  resource_group_name    = azurerm_resource_group.example.name
  location               = azurerm_resource_group.example.location
  sku_name               = var.sku_name
  os_type                = var.os_type
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Create a function app
resource "azurerm_linux_function_app" "example" {
  name                          = local.function_app_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  service_plan_id               = azurerm_service_plan.example.id
  storage_account_name          = azurerm_storage_account.example.name
  storage_account_access_key    = azurerm_storage_account.example.primary_access_key
  https_only                    = var.https_only
  public_network_access_enabled = var.public_network_access_enabled
  tags                          = var.tags
  functions_extension_version   = "~4"

  identity {
    type = "SystemAssigned"
  }

  site_config {
    minimum_tls_version = var.minimum_tls_version
    application_stack {
      dotnet_version              = var.dotnet_version
      use_dotnet_isolated_runtime = true
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME                  = var.runtime_name
    SCM_DO_BUILD_DURING_DEPLOYMENT            = "true"
    AzureWebJobsStorage                       = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};EndpointSuffix=core.windows.net;"
    WEBSITE_STORAGE_ACCOUNT_CONNECTION_STRING = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};EndpointSuffix=core.windows.net;"
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING  = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};EndpointSuffix=core.windows.net;"
    STORAGE_ACCOUNT_CONNECTION_STRING         = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};EndpointSuffix=core.windows.net;"
    INPUT_STORAGE_CONTAINER_NAME              = var.input_container_name
    OUTPUT_STORAGE_CONTAINER_NAME             = var.output_container_name
    INPUT_QUEUE_NAME                          = var.input_queue_name
    OUTPUT_QUEUE_NAME                         = var.output_queue_name
    TRIGGER_QUEUE_NAME                        = var.trigger_queue_name
    INPUT_TABLE_NAME                          = var.input_table_name
    OUTPUT_TABLE_NAME                         = var.output_table_name
    PLAYER_NAMES                              = var.player_names
    TIMER_SCHEDULE                            = var.timer_schedule
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Create an app source control configuration
resource "azurerm_app_service_source_control" "example" {
  count    = var.repo_url == "" ? 0 : 1
  app_id   = azurerm_linux_function_app.example.id
  repo_url = var.repo_url
  branch   = "main"
}
```

## Deployment Script

You can use the `deploy.sh` script to automate the deployment of all Azure resources and the .NET Azure Functions application in a single step, streamlining setup and reducing manual configuration.

```bash
#!/bin/bash

# Start azure CLI local mode session
# azlocal start_interception

# Delete any existing terraform state and plan files
rm -f terraform.tfstate terraform.tfstate.backup tfplan

# Run terraform init and apply
echo "Initializing Terraform..."
tflocal init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
tflocal plan -out=tfplan

if [[ $? != 0 ]]; then
		echo "Terraform plan failed. Exiting."
		exit 1
fi

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
tflocal apply -auto-approve tfplan

# Get the output values
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
FUNCTION_APP_NAME=$(terraform output -raw function_app_name)

# Print the variables
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Function App: $FUNCTION_APP_NAME"

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
    --type zip \
    --verbose \
		--debug

# Stop azure CLI local mode session
azlocal stop_interception
```

> **Note**  
> You can use the `azlocal` CLI as a drop-in replacement for the `az` CLI to direct all commands to the LocalStack for Azure emulator. Alternatively, run `azlocal start_interception` to automatically intercept and redirect all `az` commands to LocalStack. Likewise, the `tflocal` is a local replacement for the standard `terraform` CLI, allowing you to run Terraform commands against LocalStack's Azure emulation environment. For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

The `deploy.sh` script executes the following steps:

- Cleans up any previous Terraform state and plan files to ensure a fresh deployment.
- Initializes the Terraform working directory and downloads required plugins.
- Creates and validates a Terraform execution plan for the Azure infrastructure.
- Applies the Terraform plan to provision all necessary Azure resources.
- Extracts resource names and outputs from the Terraform deployment.
- Builds and publishes the .NET Azure Functions application.
- Packages the published application into a zip file for deployment.
- Deploys the zip package to the Azure Function App using the LocalStack Azure CLI.
- Provides verbose and debug output for troubleshooting during deployment.

> **Note**  
> Azure CLI commands use `--verbose` argument to print execution details and the `--debug` flag to show low-level REST calls for debugging. For more information, see [Get started with Azure CLI](https://learn.microsoft.com/en-us/cli/azure/get-started-with-azure-cli)


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