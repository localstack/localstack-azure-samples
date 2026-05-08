# Azure CLI Deployment

This folder contains Bash scripts for deploying an Azure Functions application with supporting Azure services using the `azlocal` CLI. The deployment creates a complete gaming scoreboard system using Azure Functions and Azure Storage Account with direct Azure CLI commands through the LocalStack Azure emulator. For more information, see [Azure Functions Sample with LocalStack for Azure](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [.NET SDK](https://dotnet.microsoft.com/en-us/download): Required for building and publishing the C# Azure Functions application
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [funclocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Functions Core Tools wrapper
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The [deploy.sh](deploy.sh) Bash script uses the `azlocal` CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

This [deploy.sh](deploy.sh) script creates the following Azure resources using Azure CLI commands:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all gaming system resources.
2. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob containers, queues, and tables for the gaming system.
3. [Azure Linux Function App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview) Serverless compute platform hosting the gaming logic with consumption plan.

The system implements a complete gaming scoreboard with multiple Azure Functions that handle HTTP requests, process blob uploads, manage queue messages, and maintain game statistics. For more information, see [Azure Functions Sample with LocalStack for Azure](../README.md).

## Provisioning Scripts 

See [deploy.sh](deploy.sh) for the complete deployment script. The script performs:

- Detects environment (LocalStack vs Azure Cloud) and selects appropriate CLI
- Creates resource group if it doesn't exist
- Creates Storage Account and retrieves access key
- Creates Function App with consumption plan
- Constructs storage connection string
- Configures Function App settings (storage, queue, table, timer configurations)
- Publishes the .NET application using `funclocal` or `func azure functionapp publish`

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
   cd samples/function-app-and-storage/dotnet/scripts
   ```

4. Make the script executable:

   ```bash
   chmod +x deploy.sh
   ```

5. Run the deployment script:

   ```bash
   ./deploy.sh
   ```

## Configuration Options

### Environment Variables

You can customize the deployment by modifying the variables at the top of `deploy.sh`:

```bash
# Customizable variables
PREFIX='myapp'              # Change resource name prefix
SUFFIX='prod'               # Change resource name suffix  
LOCATION='eastus'           # Change deployment region
RUNTIME="DOTNET-ISOLATED"   # Runtime type
RUNTIME_VERSION="9"         # Runtime version
```

### Application Settings

The script configures the following application settings for the gaming system:

| Setting | Purpose | Default Value |
|---------|---------|---------------|
| `AzureWebJobsStorage` | Functions runtime storage | Auto-generated connection string |
| `STORAGE_ACCOUNT_CONNECTION_STRING` | Application storage access | Auto-generated connection string |
| `INPUT_STORAGE_CONTAINER_NAME` | Blob input container | `input` |
| `OUTPUT_STORAGE_CONTAINER_NAME` | Blob output container | `output` |
| `INPUT_QUEUE_NAME` | Message input queue | `input` |
| `OUTPUT_QUEUE_NAME` | Message output queue | `output` |
| `TRIGGER_QUEUE_NAME` | Queue trigger name | `trigger` |
| `INPUT_TABLE_NAME` | Scoreboards table | `scoreboards` |
| `OUTPUT_TABLE_NAME` | Winners table | `winners` |
| `PLAYER_NAMES` | Game player list | Comma-separated names |
| `TIMER_SCHEDULE` | Scheduled function trigger | `0 */1 * * * *` (every minute) |
| `FUNCTIONS_WORKER_RUNTIME` | Runtime specification | `dotnet-isolated` |

### LocalStack-Specific Commands

1. `azlocal start-interception`:
   - Redirects Azure CLI calls to LocalStack endpoints
   - Enables local development without Azure subscription
   - Maintains compatibility with standard Azure CLI syntax

2. `funclocal azure functionapp publish`:
   - Deploys function app to LocalStack Azure emulator
   - Wraps the Azure Functions Core Tools
   - Provides local testing environment for Azure Functions

3. `azlocal stop-interception`:
   - Restores normal Azure CLI behavior
   - Cleans up LocalStack session state
   - Returns CLI to standard Azure cloud operations

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

# List storage queues
az storage queue list \
  --account-name localstoragetest \
  --output table \
  --only-show-errors

# List storage tables
az storage table list \
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

- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [Azure Functions CLI Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local)
- [Azure Functions Methods Documentation](../src/sample/Methods.md) - Detailed documentation of all implemented functions
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
