# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning Azure services in LocalStack for Azure. Refer to the [Azure Web App with Azure SQL Database and Azure Key Vault](../README.md) guide for details about the sample application.

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Terraform](https://developer.hashicorp.com/terraform/downloads): Infrastructure as Code tool for provisioning Azure resources
- [.NET SDK 10.0](https://dotnet.microsoft.com/en-us/download/dotnet/10.0)
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/): LocalStack command-line interface (proxies the Azure CLI via `lstk az`)
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing lstk CLI

Deploying to LocalStack requires the `lstk` CLI, which routes Azure CLI commands to the emulator (run `lstk az start-interception` before deploying). Install it using Homebrew:

```bash
brew install localstack/tap/lstk
```

or npm:

```bash
npm install -g @localstack/lstk
```

Alternatively, download a pre-built binary from the [lstk releases page](https://github.com/localstack/lstk/releases). For more information, see the [lstk CLI documentation](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/) and the [lstk GitHub repository](https://github.com/localstack/lstk).

## Architecture Overview

The [main.tf](main.tf) Terraform module creates the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all resources in the sample.
2. [Azure SQL Server](https://learn.microsoft.com/en-us/azure/azure-sql/database/sql-database-paas-overview): Logical server hosting one or more Azure SQL Databases.
3. [Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/): The `PlannerDB` database storing relational vacation activity data.
4. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): The compute resource that hosts the web application.
5. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): Hosts the ASP.NET Core Razor Pages single-page application (*Vacation Planner*), connected to Azure SQL Database.
6. [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview): Stores the SQL connection string as a secret and a self-signed certificate for HTTPS.
7. [App Service Source Control](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/create-or-update-source-control?view=rest-appservice-2024-11-01): (Optional) Configures automatic deployment from a public GitHub repository.

The system implements a Vacation Planner web application that stores and retrieves activity data from Azure SQL Database. For more information, see [Azure Web App with Azure SQL Database and Azure Key Vault](../README.md).

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
  metadata_host="azure.localhost.localstack.cloud:4566"

  # Set the subscription ID to a dummy value when using LocalStack's Azure emulator.
  subscription_id = "00000000-0000-0000-0000-000000000000"
}
```

## Deployment

You can set up the Azure emulator by utilizing LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/) to obtain your Auth Token and specify it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure). To pull the Azure Docker image, execute the following command:

```bash
docker pull localstack/localstack-azure
```

Start the LocalStack Azure emulator using the localstack CLI, execute the following command:

```bash
# Set the authentication token
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>

# Start the LocalStack Azure emulator
IMAGE_NAME=localstack/localstack-azure localstack start -d
localstack wait -t 60

# Route all Azure CLI calls to the LocalStack Azure emulator
lstk az start-interception
```

Navigate to the `terraform` folder:

```bash
cd samples/web-app-sql-database/dotnet/terraform
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
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
SQL_SERVER_NAME="${PREFIX}-sqlserver-${SUFFIX}"
SQL_DATABASE_NAME='PlannerDB'
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
KEY_VAULT_NAME="${PREFIX}-kv-${SUFFIX}"
SECRET_NAME="${PREFIX}-secret-${SUFFIX}"

# Check resource group
echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
az group show \
--name "$RESOURCE_GROUP_NAME" \
--output table

# Check Azure Web App
echo -e "\n[$WEB_APP_NAME] web app:\n"
az webapp show \
--name "$WEB_APP_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "{name:name, state:state, defaultHostName:defaultHostName}" \
--output table

# Check Azure SQL Server
echo -e "\n[$SQL_SERVER_NAME] SQL server:\n"
az sql server show \
--name "$SQL_SERVER_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--output table

# Check Azure SQL Database
echo -e "\n[$SQL_DATABASE_NAME] SQL database:\n"
az sql db show \
--name "$SQL_DATABASE_NAME" \
--server "$SQL_SERVER_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--output table

# Check Azure Key Vault
echo -e "\n[$KEY_VAULT_NAME] Key Vault:\n"
az keyvault show \
--name "$KEY_VAULT_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--output table

# Check Key Vault secret
echo -e "\n[$SECRET_NAME] Key Vault secret:\n"
az keyvault secret show \
--vault-name "$KEY_VAULT_NAME" \
--name "$SECRET_NAME" \
--query "{name:name, enabled:attributes.enabled, created:attributes.created}" \
--output table

# Print the list of resources in the resource group
echo -e "\nListing resources in resource group [$RESOURCE_GROUP_NAME]...\n"
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table 
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
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
