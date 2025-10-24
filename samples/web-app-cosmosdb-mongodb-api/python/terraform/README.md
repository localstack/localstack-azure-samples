# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning Azure services in LocalStack for Azure. Refer to the [Azure Web App with CosmosDB for MongoDB](../README.md) guide for details about the sample application.

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

The Terraform modules deploy the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all resources in the sample.
2. [Azure CosmosDB Account (MongoDB API)](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/introduction): A globally distributed database account configured for MongoDB workloads, with multi-region failover.
3. [MongoDB Database](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/overview): The `sampledb` database for storing application data.
4. [MongoDB Collection](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/overview): The `activities` collection within `sampledb` for storing vacation activity records.
5. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): The compute resource that hosts the web application.
6. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): Hosts the Python Flask single-page application (*Vacation Planner*), connected to CosmosDB for MongoDB.
7. [App Service Source Control](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/create-or-update-source-control?view=rest-appservice-2024-11-01): (Optional) Configures automatic deployment from a public GitHub repository.

The web app allows users to plan and manage vacation activities, storing all activity data in the CosmosDB-backed MongoDB collection. All resources are provisioned and configured using Terraform for easy reproducibility and local development with LocalStack for Azure.

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
  cosmosdb_account_name = "${var.prefix}-mongodb-${var.suffix}"
  app_service_plan_name = "${var.prefix}-app-service-plan-${var.suffix}"
  web_app_name          = "${var.prefix}-webapp-${var.suffix}"
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  location = var.location
  name     = var.resource_group_name
  tags     = var.tags
}

# Create a cosmosdb account
resource "azurerm_cosmosdb_account" "example" {
  name                       = local.cosmosdb_account_name
  resource_group_name        = azurerm_resource_group.example.name
  location                   = azurerm_resource_group.example.location
  offer_type                 = "Standard"
  kind                       = "MongoDB"
  automatic_failover_enabled = false
  tags                       = var.tags

  consistency_policy {
    consistency_level       = var.consistency_level
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  geo_location {
    location          = var.primary_region
    failover_priority = 0
  }

  geo_location {
    location          = var.secondary_region
    failover_priority = 1
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_cosmosdb_mongo_database" "example" {
  name                = var.cosmosdb_database_name
  resource_group_name = azurerm_resource_group.example.name
  account_name        = azurerm_cosmosdb_account.example.name
  throughput          = 400
}

resource "azurerm_cosmosdb_mongo_collection" "example" {
  name                = var.cosmosdb_collection_name
  resource_group_name = azurerm_resource_group.example.name
  account_name        = azurerm_cosmosdb_account.example.name
  database_name       = azurerm_cosmosdb_mongo_database.example.name

  default_ttl_seconds = "777"
  shard_key           = "username"
  throughput          = 400

  # Dynamically create the 'index' blocks using a for_each loop over the variable
  dynamic "index" {
    # The for_each expression iterates over the list of keys from the variable
    for_each = var.mongodb_index_keys
    content {
      # The value of the current item in the iteration (e.g., "$**", "_id", etc.)
      keys = [index.value]
    }
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

# Create a web app
resource "azurerm_linux_web_app" "example" {
  name                          = local.web_app_name
  resource_group_name           = azurerm_resource_group.example.name
  location                      = azurerm_resource_group.example.location
  service_plan_id               = azurerm_service_plan.example.id
  https_only                    = var.https_only
  public_network_access_enabled = var.public_network_access_enabled
  client_affinity_enabled       = false
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = var.always_on
    http2_enabled       = var.http2_enabled
    minimum_tls_version = var.minimum_tls_version
    application_stack {
      python_version = var.python_version
    }
  }

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    COSMOSDB_CONNECTION_STRING     = azurerm_cosmosdb_account.example.primary_mongodb_connection_string
    COSMOSDB_DATABASE_NAME         = azurerm_cosmosdb_mongo_database.example.name
    COSMOSDB_COLLECTION_NAME       = var.cosmosdb_collection_name
    LOGIN_NAME                     = var.login_name
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Deploy code from a public GitHub repo
resource "azurerm_app_service_source_control" "example" {
  count                  = var.repo_url == "" ? 0 : 1
  app_id                 = azurerm_linux_web_app.example.id
  repo_url               = var.repo_url
  branch                 = "main"
  use_manual_integration = true
  use_mercurial          = false
}
```

## Deployment Script

You can use the `deploy.sh` script to automate the deployment of all Azure resources and the .NET Azure Functions application in a single step, streamlining setup and reducing manual configuration.

```bash
#!/bin/bash

# Variables
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

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

if [[ $? != 0 ]]; then
		echo "Terraform apply failed. Exiting."
		exit 1
fi

# Get the output values
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
WEB_APP_NAME=$(terraform output -raw web_app_name)

# Print the variables
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Web App: $WEB_APP_NAME"

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
azlocal webapp deploy \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$WEB_APP_NAME" \
  --src-path planner_website.zip \
  --type zip \
  --async true

# Remove the zip package of the web app
rm "$ZIPFILE"
```

> **Note**  
> You can use the `azlocal` CLI as a drop-in replacement for the `az` CLI to direct all commands to the LocalStack for Azure emulator. Alternatively, run `azlocal start_interception` to automatically intercept and redirect all `az` commands to LocalStack. Likewise, the `tflocal` is a local replacement for the standard `terraform` CLI, allowing you to run Terraform commands against LocalStack's Azure emulation environment. For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

The `deploy.sh` script executes the following steps:

- Cleans up any previous Terraform state and plan files to ensure a fresh deployment.
- Initializes the Terraform working directory and downloads required plugins.
- Creates and validates a Terraform execution plan for the Azure infrastructure.
- Applies the Terraform plan to provision all necessary Azure resources.
- Extracts resource names and outputs from the Terraform deployment.
- Packages the code of the web application into a zip file for deployment.
- Deploys the zip package to the Azure Web App using the LocalStack Azure CLI.

## Configuration

Before deploying the Terraform modules, update the `terraform.tfvars` file with your specific values:

```hcl
resource_group_name      = "local-rg"
location                 = "westeurope"
azure_client_id          = "<your-azure-client-id>"
azure_client_secret      = "<your-azure-client-secret>"
azure_tenant_id          = "<your-azure-tenant-id>"
azure_subscription_id    = "<your-azure-subscription-id>"
cosmosdb_database_name   = "sampledb"
cosmosdb_collection_name = "activities"
```

Replace the placeholder values (enclosed in `< >`) with your actual Azure credentials and desired resource names. This ensures Terraform provisions resources with the correct configuration for your environment.

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

- [Azure Web Apps Documentation](https://learn.microsoft.com/en-us/azure/app-service/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)