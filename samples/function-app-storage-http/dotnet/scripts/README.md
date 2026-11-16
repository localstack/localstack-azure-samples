# Azure CLI Deployment

This folder contains Bash scripts for deploying an Azure Functions application with supporting Azure services using the `lstk` CLI. The deployment creates a complete gaming scoreboard system using Azure Functions and Azure Storage Account with direct Azure CLI commands through the LocalStack Azure emulator. For more information, see [Azure Functions Sample with LocalStack for Azure](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [.NET SDK](https://dotnet.microsoft.com/en-us/download): Required for building and publishing the C# Azure Functions application
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

This [deploy.sh](deploy.sh) script creates the following Azure resources using Azure CLI commands:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all gaming system resources.
2. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob containers, queues, and tables for the gaming system.
3. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): A Linux plan of the Basic (B1) tier that hosts the function app. The script doesn't use the Linux Consumption plan, because .NET 9 is the last .NET version that it supports ([Supported languages in Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/supported-languages)).
4. [Azure Linux Function App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview): Hosts the gaming logic on the .NET 10 isolated worker runtime.
5. [Log Analytics Workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-workspace-overview): Stores the telemetry of the Application Insights resource, and the logs and metrics that the diagnostic settings send to it.
6. [Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview): A workspace-based resource that collects the invocations of the functions and the log records of the functions and of the Functions host, which the host sends to the connection string of the `APPLICATIONINSIGHTS_CONNECTION_STRING` app setting.
7. [Diagnostic Settings](https://learn.microsoft.com/en-us/azure/azure-monitor/data-collection/diagnostic-settings): Send the resource logs (`FunctionAppLogs`) and the platform metrics of the function app, and the platform metrics of the App Service plan, to the Log Analytics workspace.

The system implements a complete gaming scoreboard with multiple Azure Functions that handle HTTP requests, process blob uploads, manage queue messages, and maintain game statistics. For more information, see [Azure Functions Sample with LocalStack for Azure](../README.md).

## Provisioning Scripts 

See [deploy.sh](deploy.sh) for the complete deployment script. The script performs:

- Creates resource group if it doesn't exist
- Creates Storage Account and retrieves access key
- Creates a Log Analytics workspace and a workspace-based Application Insights resource
- Creates a Linux App Service plan of the Basic (B1) tier
- Creates the Function App on the plan, connected to the Application Insights resource
- Constructs storage connection string
- Configures Function App settings (storage, queue, table, timer configurations)
- Creates the diagnostic settings that send the logs and metrics of the Function App and the metrics of the App Service plan to the Log Analytics workspace
- Builds and publishes the .NET application in Release configuration
- Creates deployment zip package from published output
- Deploys the zip to Azure Function App using `az functionapp deploy`

## Deployment

1. You can set up the Azure emulator by utilizing LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/) to obtain your Auth Token and specify it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure). To pull the Azure Docker image, execute the following command:

   ```bash
   docker pull localstack/localstack-azure
   ```

2. Start the LocalStack Azure emulator with the lstk CLI:

   ```bash
   export LOCALSTACK_AUTH_TOKEN=<your_auth_token>
   lstk start --type azure
   ```

3. Navigate to the scripts directory

   ```bash
   cd samples/function-app-storage-http/dotnet/scripts
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
RUNTIME_VERSION="10"        # Runtime version
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

1. `lstk az start-interception`:
   - Redirects Azure CLI calls to LocalStack endpoints
   - Enables local development without Azure subscription
   - Maintains compatibility with standard Azure CLI syntax

2. `az functionapp deploy`:
   - Deploys the zipped publish output to the function app
   - Works identically against LocalStack and Azure
   - Uses the standard Azure CLI zip deployment mechanism

3. `lstk az stop-interception`:
   - Restores normal Azure CLI behavior
   - Cleans up LocalStack session state
   - Returns CLI to standard Azure cloud operations

## Validation

After deployment, you can use the `validate.sh` script to verify that all resources were created and configured correctly:

```bash
#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
FUNCTION_APP_NAME="${PREFIX}-functionapp-${SUFFIX}"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-insights-${SUFFIX}"

# Check resource group
az group show \
  --name $RESOURCE_GROUP_NAME \
  --output table

# List resources
az resource list \
  --resource-group $RESOURCE_GROUP_NAME \
  --output table

# Check function app status
az functionapp show  \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --output table

# Check storage account properties
az storage account show \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --output table

# Check Log Analytics workspace
az monitor log-analytics workspace show \
  --resource-group $RESOURCE_GROUP_NAME \
  --workspace-name $LOG_ANALYTICS_NAME \
  --query '{Name:name,Location:location,ResourceGroup:resourceGroup,Sku:sku.name,RetentionInDays:retentionInDays}' \
  --output table \
  --only-show-errors

# Check Application Insights component
az monitor app-insights component show \
  --app $APPLICATION_INSIGHTS_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --query '{Name:name,Location:location,ResourceGroup:resourceGroup,ApplicationType:applicationType,WorkspaceResourceId:workspaceResourceId}' \
  --output table \
  --only-show-errors

# Check the diagnostic settings of the function app and of its App Service plan
FUNCTION_APP_ID=$(az functionapp show \
  --name "$FUNCTION_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query id \
  --output tsv \
  --only-show-errors)
APP_SERVICE_PLAN_ID=$(az functionapp show \
  --name "$FUNCTION_APP_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query appServicePlanId \
  --output tsv \
  --only-show-errors)

echo -e "\n[$FUNCTION_APP_NAME] function app diagnostic settings:\n"
az monitor diagnostic-settings list \
  --resource "$FUNCTION_APP_ID" \
  --query "[].{Name:name,Logs:join(', ', logs[?enabled].category),Metrics:join(', ', metrics[?enabled].category)}" \
  --output table \
  --only-show-errors

echo -e "\nApp Service plan diagnostic settings:\n"
az monitor diagnostic-settings list \
  --resource "$APP_SERVICE_PLAN_ID" \
  --query "[].{Name:name,Metrics:join(', ', metrics[?enabled].category)}" \
  --output table \
  --only-show-errors

# List storage containers
az storage container list \
  --account-name $STORAGE_ACCOUNT_NAME \
  --output table \
  --only-show-errors

# List storage queues
az storage queue list \
  --account-name $STORAGE_ACCOUNT_NAME \
  --output table \
  --only-show-errors

# List storage tables
az storage table list \
  --account-name $STORAGE_ACCOUNT_NAME \
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
- [Azure Functions Methods Documentation](../METHODS.md) - Detailed documentation of all implemented functions
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
