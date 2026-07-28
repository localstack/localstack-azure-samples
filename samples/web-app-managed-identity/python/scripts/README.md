# Azure CLI Deployment

This directory includes Bash scripts designed for deploying and testing the sample Web App utilizing the `lstk` CLI. Refer to the [Azure Web App with Managed Identity](../README.md) guide for details about the sample application.

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

The [user-assigned.sh](user-assigned.sh) and [system-assigned.sh](system-assigned.sh) Bash scripts create the following Azure resources using Azure CLI commands:

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage for persisting vacation activity data. The web application stores each activity as a JSON blob file in the `activities` container.
2. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): Defines the compute resources (CPU, memory, and scaling options) that host the web application.
3. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): Hosts the Python Flask-based *Vacation Planner* application. The web app uses managed identity to securely access the Azure Storage Account without requiring explicit credentials.
4. [Managed Identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview): Provides secure, credential-free authentication between the web app and storage account. Supports both system-assigned and user-assigned identity types.
5. [Role Assignment](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments): Grants the web app's managed identity the *Storage Blob Data Contributor* role, enabling read/write access to blob containers.
6. [App Service Source Control](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/create-or-update-source-control?view=rest-appservice-2024-11-01): (Optional) Enables continuous deployment from a Git repository for automated application updates.

The web app allows users to plan and manage vacation activities, storing all activity data as blob files in the `activities` containers in the [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview). For more information, see [Azure Web App with Managed Identity](../README.md).

## Provisioning Scripts 

## Automation Scripts

This sample provides two bash scripts to streamline the deployment process by automating the provisioning of Azure resources and the sample application:

- [user-assigned.sh](user-assigned.sh): Configures the Azure Web App with a *user-assigned managed identity*
- [system-assigned.sh](system-assigned.sh): Configures the Azure Web App with a *system-assigned managed identity*

See the script files for complete implementation. The scripts perform the following operations:

- Detect environment (LocalStack or Azure Cloud) and select appropriate CLI
- Create resource group if it doesn't exist
- Provision storage account and retrieve access keys and endpoints
- Create blob container for activity data
- Create App Service Plan with Linux runtime
- Create user-assigned managed identity (user-assigned script only)
- Retrieve identity client ID, principal ID, and resource ID
- Create web app with specified Python runtime
- Assign managed identity to web app
- Configure Storage Blob Data Contributor role assignment with retry logic
- Set web app configuration settings (storage URL, container name, client ID)
- Package application code into zip file
- Deploy zip package to Azure Web App
- Clean up temporary artifacts

These scripts eliminate manual configuration steps and enable one-command deployment of the entire infrastructure.

> [!NOTE]
> You can use `lstk az` to proxy Azure CLI commands to the LocalStack for Azure emulator. Alternatively, run `lstk az start-interception` to automatically intercept and redirect all `az` commands to LocalStack. To revert back to the default behavior and send commands to the Azure cloud, run `lstk az stop-interception`.

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
cd samples/web-app-managed-identity/python/scripts
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
RESOURCE_GROUP_NAME="${PREFIX}-web-app-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
CONTAINER_NAME='activities'
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}"

# Check resource group
echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
az group show \
	--name "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check App Service Plan
echo -e "\n[$APP_SERVICE_PLAN_NAME] app service plan:\n"
az appservice plan show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_SERVICE_PLAN_NAME" \
	--output table \
	--only-show-errors

# Check Azure Web App
echo -e "\n[$WEB_APP_NAME] web app:\n"
az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,State:state,Location:location,DefaultHostName:defaultHostName}' \
	--output table \
	--only-show-errors

# Check user-assigned managed identity
echo -e "\n[$MANAGED_IDENTITY_NAME] managed identity:\n"
az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,ClientId:clientId,PrincipalId:principalId}' \
	--output table \
	--only-show-errors

# Check storage account
echo -e "\n[$STORAGE_ACCOUNT_NAME] storage account:\n"
az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,Kind:kind,Sku:sku.name}' \
	--output table \
	--only-show-errors

# List storage containers
echo -e "\n[$STORAGE_ACCOUNT_NAME] storage containers:\n"
az storage container list \
	--account-name "$STORAGE_ACCOUNT_NAME" \
	--output table \
	--only-show-errors

# List resources
echo -e "\n[$RESOURCE_GROUP_NAME] all resources:\n"
az resource list \
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

- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
