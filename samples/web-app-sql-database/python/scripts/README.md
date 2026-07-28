# Azure CLI Deployment

This directory includes Bash scripts designed for deploying and testing the sample Web App utilizing the `lstk` CLI. For further details about the sample application, refer to the [Azure Web App with Azure SQL Database and Azure Key Vault](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/): LocalStack command-line interface (proxies the Azure CLI via `lstk az`)
- [Python](https://www.python.org/downloads/): Python runtime (version 3.12 or above)
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

The [deploy.sh](deploy.sh) Bash script creates the following Azure resources using Azure CLI commands:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all resources
2. [Azure SQL Server](https://learn.microsoft.com/en-us/azure/azure-sql/database/sql-database-paas-overview): Logical server hosting one or more Azure SQL Databases.
3. [Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/): The `PlannerDB` database storing relational vacation activity data.
4. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): The compute resource that hosts the web application.
5. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): Hosts the Python Flask single-page application (*Vacation Planner*), connected to Azure SQL Database.
6. [App Service Source Control](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/create-or-update-source-control?view=rest-appservice-2024-11-01): (Optional) Configures automatic deployment from a public GitHub repository.
7. [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview): Stores the SQL connection string in a secret.

The system implements a Vacation Planner web application that stores and retrieves activity data from Azure SQL Database. For more information, see [Azure Web App with Azure SQL Database and Azure Key Vault](../README.md).

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

Navigate to the `scripts` folder:

```bash
cd samples/web-app-sql-database/python/scripts
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
# Check resource group
az group show \
--name local-rg \
--output table

# List resources
az resource list \
--resource-group local-rg \
--output table

# Check Azure Web App
az webapp show \
--name local-webapp-test \
--resource-group local-rg \
--output table

# Check Azure SQL Server
az sql server show \
--name local-sqlserver-test \
--resource-group local-rg \
--output table

# Check Azure SQL Database
az sql db show \
--name PlannerDB \
--server local-sqlserver-test \
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
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
