# Bicep Deployment

This directory contains the Bicep template and a deployment script for provisioning Azure services in LocalStack for Azure. Refer to the [Azure Functions App with Managed Identity](../README.md) guide for details about the sample application.

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep): VS Code extension for Bicep language support and IntelliSense
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/): LocalStack command-line interface (proxies the Azure CLI via `lstk az`)
- [Python](https://www.python.org/downloads/): Python runtime (version 3.13 or above)
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

The [deploy.sh](deploy.sh) script creates the [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli) for all the Azure resources, while the [main.bicep](main.bicep) Bicep module creates the following Azure resources:

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage with `input` and `output` containers for storing text blobs processed by the function app.
2. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): Defines the compute resources (CPU, memory, and scaling options) that host the Azure Functions app.
3. [Azure Functions App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview): Hosts the serverless application that processes text blobs. The function app uses managed identity to securely access the Azure Storage Account without requiring explicit credentials.
4. [Managed Identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview): Provides secure, credential-free authentication between the Azure Functions app and storage account. Supports both system-assigned and user-assigned identity types.
5. [Role Assignment](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments): Grants the Azure Functions app's managed identity the Storage Blob Data Contributor and Storage Queue Data Contributor roles, enabling read/write access to blob containers and queues for processing text data.

For more information on the sample application, see [Azure Functions App with Managed Identity](../README.md).

## Configuration

Before deploying the `main.bicep` template, update the `bicep.bicepparam` file with your specific values. Note that the `deploy.sh` script overrides some of these parameters.

```bicep
using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param runtimeName = 'python'
param runtimeVersion = '3.13'
```

## Provisioning Scripts

The [deploy.sh](deploy.sh) script automates the deployment of all Azure resources and the sample application in a single step. Before running the script, customize the variable values based on your needs. In particular, use the `MANAGED_IDENTITY_TYPE` variable to specify the type of managed identity to provision: `SystemAssigned` or `UserAssigned`.

> **Note**  
> You can use `lstk az` to proxy Azure CLI commands to the LocalStack for Azure emulator. Alternatively, run `lstk az start-interception` to automatically intercept and redirect all `az` commands to LocalStack. For more information, see the [lstk CLI documentation](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/).

The [deploy.sh](deploy.sh) script executes the following steps:

- Specifies the variables used during deployment
- Creates the resource group if it does not exist
- Conditionally validates the `main.bicep` module to check its syntax is correct and all parameters make sense
- Conditionally runs a what-if deployment to execute a dry run to preview the resources that will be created, updated, or deleted
- Runs the `main.bicep` template to create all the Azure resources
- Collects important information from the deployment (like resource names) for later use
- Uses jq (a JSON tool) to extract the names of resources we just created
- Creates zip archive in format expected by Function App
- Uploads pre-built application package to the newly created Function App

> **Note**  
> Azure CLI commands use `--verbose` argument to print execution details and the `--debug` flag to show low-level REST calls for debugging. For more information, see [Get started with Azure CLI](https://learn.microsoft.com/en-us/cli/azure/get-started-with-azure-cli)

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

Navigate to the `bicep` folder:

```bash
cd samples/function-app-managed-identity/python/bicep
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

# Check function app status
az functionapp show  \
  --name local-func-test \
  --resource-group local-rg \
  --output table

# Check storage account properties
az storage account show \
  --name localstoragetest \
  --resource-group local-rg \
  --output table

# List storage containers
az storage container list \
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

- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Bicep Language Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
