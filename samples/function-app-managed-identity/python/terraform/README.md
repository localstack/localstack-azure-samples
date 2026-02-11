# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning Azure services in LocalStack for Azure. Refer to the [Azure Functions App with Managed Identity](../README.md) guide for details about the sample application.

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Terraform](https://developer.hashicorp.com/terraform/downloads): Infrastructure as Code tool for provisioning Azure resources
- [Python](https://www.python.org/downloads/): Python runtime (version 3.13 or above)
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

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage with `input` and `output` containers for storing text blobs processed by the function app.
2. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): Defines the compute resources (CPU, memory, and scaling options) that host the Azure Functions app.
3. [Azure Functions App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview): Hosts the serverless application that processes text blobs. The function app uses managed identity to securely access the Azure Storage Account without requiring explicit credentials.
4. [Managed Identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview): Provides secure, credential-free authentication between the Azure Functions app and storage account. Supports both system-assigned and user-assigned identity types.
5. [Role Assignment](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments): Grants the Azure Functions app's managed identity the Storage Blob Data Contributor and Storage Queue Data Contributor roles, enabling read/write access to blob containers and queues for processing text data.

For more information on the sample application, see [Azure Functions App with Managed Identity](../README.md).

## Terraform Modules

Below is a summary of the key Terraform modules included in this deployment:

- **`main.tf`**: Defines all Azure resources and their configuration.
- **`variables.tf`**: Declares input variables and validation rules.
- **`outputs.tf`**: Specifies output values after deployment.
- **`providers.tf`**: Configures the Terraform provider for Azure.

Below you can read the declarative code in HashiCorp Configuration Language (HCL). The `main.tf` module uses conditional provisioning for the user-assigned managed identity and role assignments resources. In Terraform, you can use the `count` argument in a conditional expression to decide whether creating resources or not. For example, the `count = var.managed_identity_type == "UserAssigned" ? 1 : 0` expression instructs Terraform to create the user-assigned managed identity resource when the value of the variable named `managed_identity_type` is set to `UserAssigned`. Refer to ​​[Conditional Expressions](https://developer.hashicorp.com/terraform/language/expressions/conditionals) for more information.

```terraform
# Local Variables
locals {
  resource_group_name   = "${var.prefix}-rg"
  storage_account_name  = "${var.prefix}storage${var.suffix}"
  app_service_plan_name = "${var.prefix}-app-service-plan-${var.suffix}"
  function_app_name     = "${var.prefix}-functionapp-${var.suffix}"
  managed_identity_name = "${var.prefix}-identity-${var.suffix}"
}

# Create a resource group
resource "azurerm_resource_group" "example" {
  location = var.location
  name     = local.resource_group_name
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

# Create input storage container
resource "azurerm_storage_container" "input" {
  name                  = var.input_container_name
  storage_account_id    = azurerm_storage_account.example.id
  container_access_type = "private"
}

# Create output storage container
resource "azurerm_storage_container" "output" {
  name                  = var.output_container_name
  storage_account_id    = azurerm_storage_account.example.id
  container_access_type = "private"
}

# Conditionally create a user assigned identity for the function app
resource "azurerm_user_assigned_identity" "identity" {
  count = var.managed_identity_type == "UserAssigned" ? 1 : 0

  name                = local.managed_identity_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
}

# Assign Storage Blob Data Contributor role to the function app identity
resource "azurerm_role_assignment" "blob_contributor" {
  scope                = azurerm_storage_account.example.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.managed_identity_type == "UserAssigned" ? azurerm_user_assigned_identity.identity[0].principal_id : azurerm_linux_function_app.example.identity[0].principal_id
}

# Assign Storage Queue Data Contributor role to the function app identity
resource "azurerm_role_assignment" "queue_contributor" {
  scope                = azurerm_storage_account.example.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = var.managed_identity_type == "UserAssigned" ? azurerm_user_assigned_identity.identity[0].principal_id : azurerm_linux_function_app.example.identity[0].principal_id
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
    type = var.managed_identity_type
    identity_ids = var.managed_identity_type == "UserAssigned" ? [
      azurerm_user_assigned_identity.identity[0].id
    ] : []
  }

  site_config {
    always_on           = var.always_on
    minimum_tls_version = var.minimum_tls_version
    application_stack {
      python_version = var.python_version
    }
  }

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT                     = "true"
    ENABLE_ORYX_BUILD                                  = "true"
    AZURE_CLIENT_ID                                    = var.managed_identity_type == "UserAssigned" ? azurerm_user_assigned_identity.identity[0].client_id : ""
    AzureWebJobsStorage                                = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.example.name};AccountKey=${azurerm_storage_account.example.primary_access_key};EndpointSuffix=core.windows.net;"
    STORAGE_ACCOUNT_CONNECTION_STRING__blobServiceUri  = azurerm_storage_account.example.primary_blob_endpoint
    STORAGE_ACCOUNT_CONNECTION_STRING__queueServiceUri = azurerm_storage_account.example.primary_queue_endpoint
    STORAGE_ACCOUNT_CONNECTION_STRING__tableServiceUri = azurerm_storage_account.example.primary_table_endpoint
    INPUT_STORAGE_CONTAINER_NAME                       = var.input_container_name
    OUTPUT_STORAGE_CONTAINER_NAME                      = var.output_container_name
    FUNCTIONS_WORKER_RUNTIME                           = var.runtime_name
    FUNCTIONS_EXTENSION_VERSION                        = "~4"
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

You can use the `deploy.sh` script to automate the deployment of all Azure resources and the sample application in a single step, streamlining setup and reducing manual configuration. Before running the script, customize the variable values based on your needs. In particular, use the `MANAGED_IDENTITY_TYPE` variable to specify the type of managed identity to provision: `SystemAssigned` or `UserAssigned`.

```bash
#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
MANAGED_IDENTITY_TYPE='UserAssigned' # SystemAssigned or UserAssigned
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="function_app.zip"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Run terraform init and apply
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using tflocal and azlocal for LocalStack emulator environment and ."
	TERRAFORM="tflocal"
	AZ="azlocal"
else
	echo "Using standard terraform and az for AzureCloud environment."
	TERRAFORM="terraform"
	AZ="az"
fi

echo "Initializing Terraform..."
$TERRAFORM init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
$TERRAFORM plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "managed_identity_type=$MANAGED_IDENTITY_TYPE"

if [[ $? != 0 ]]; then
	echo "Terraform plan failed. Exiting."
	exit 1
fi

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
$TERRAFORM apply -auto-approve tfplan

if [[ $? != 0 ]]; then
	echo "Terraform apply failed. Exiting."
	exit 1
fi

# Get the output values
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
FUNCTION_APP_NAME=$(terraform output -raw function_app_name)

if [[ -z "$RESOURCE_GROUP_NAME" || -z "$FUNCTION_APP_NAME" ]]; then
	echo "Resource Group Name or Function App Name is empty. Exiting."
	exit 1
fi

# Print the variables
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Function App: $FUNCTION_APP_NAME"

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
> You can use the `azlocal` CLI as a drop-in replacement for the `az` CLI to direct all commands to the LocalStack for Azure emulator. Alternatively, run `azlocal start_interception` to automatically intercept and redirect all `az` commands to LocalStack. Likewise, the `tflocal` is a local replacement for the standard `terraform` CLI, allowing you to run Terraform commands against LocalStack's Azure emulation environment. For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

The `deploy.sh` script executes the following steps:

- Cleans up any previous Terraform state and plan files to ensure a fresh deployment.
- Initializes the Terraform working directory and downloads required plugins.
- Creates and validates a Terraform execution plan for the Azure infrastructure.
- Applies the Terraform plan to provision all necessary Azure resources.
- Extracts resource names and outputs from the Terraform deployment.
- Packages the code of the serverless application into a zip file for deployment.
- Deploys the zip package to the Azure Functions App using the LocalStack Azure CLI.

## Configuration

Before deploying the Terraform modules, update the `terraform.tfvars` file with your specific values:

```hcl
location            = "westeurope"
python_version      = "3.13"
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
cd samples/function-app-managed-identity/python/terraform
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

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)