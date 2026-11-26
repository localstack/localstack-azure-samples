# Terraform Deployment

This directory contains Terraform modules and `deploy.sh` deployment script for creating Azure services. For more information, see [Azure Functions Sample with LocalStack for Azure](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Terraform](https://developer.hashicorp.com/terraform/downloads): Infrastructure as Code tool for provisioning Azure resources
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

The [main.tf](main.tf) Terraform module creates the following Azure resources:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all gaming system resources
2. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob containers, queues, and tables for the gaming system
3. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): Hosting plan for the Azure Functions application
4. [Azure Linux Function App](https://learn.microsoft.com/en-us/azure/azure-functions/functions-overview): Hosts the gaming logic on the App Service plan
5. [Log Analytics Workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-workspace-overview): Stores the telemetry of the Application Insights resource, and the logs and metrics that the diagnostic settings send to it.
6. [Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview): A workspace-based resource that collects the invocations of the functions and the log records of the functions and of the Functions host, which the host sends to the connection string of the `APPLICATIONINSIGHTS_CONNECTION_STRING` app setting.
7. [Diagnostic Settings](https://learn.microsoft.com/en-us/azure/azure-monitor/data-collection/diagnostic-settings): Send the resource logs (`FunctionAppLogs`) and the platform metrics of the function app, and the platform metrics of the App Service plan, to the Log Analytics workspace.

The system implements a complete gaming scoreboard with multiple Azure Functions that handle HTTP requests, process blob uploads, manage queue messages, and maintain game statistics.

## Provisioning Scripts

See [deploy.sh](deploy.sh) for the complete deployment automation. The script performs:

- Runs the standard `terraform` and `az` CLIs (run `lstk az start-interception` beforehand to route all Azure CLI calls to the LocalStack emulator)
- Initializes Terraform and downloads required providers
- Creates and validates Terraform execution plan with custom variables
- Applies Terraform configuration to provision Azure resources
- Extracts output values (resource group name, function app name)
- Builds and publishes the .NET application in Release configuration
- Creates deployment zip package from published output
- Deploys the zip to Azure Function App using Azure CLI

## Configuration

`providers.tf` hardcodes no endpoint and no subscription. `deploy.sh` exports the variables the [Azure Provider for Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) reads natively, so the same files run unmodified against the LocalStack emulator and against Azure:

| Variable                               | Exported when                         | Value                                                     |
| -------------------------------------- | ------------------------------------- | --------------------------------------------------------- |
| `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID` | always                                | `az account show`                                         |
| `ARM_METADATA_HOSTNAME`                | the active `az cloud` is `LocalStack` | host of `az cloud show --query endpoints.resourceManager` |

The provider discovers every endpoint of the emulator from `ARM_METADATA_HOSTNAME`, and authenticates with the Azure CLI session on both targets. Against Azure, `deploy.sh` unsets `ARM_METADATA_HOSTNAME`, so the provider uses the endpoints of the public cloud. Running `terraform` directly, rather than through `deploy.sh`, needs these variables exported.

## Deployment

You can set up the Azure emulator by utilizing LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/) to obtain your Auth Token and specify it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure). To pull the Azure Docker image, execute the following command:

```bash
docker pull localstack/localstack-azure
```

Start the LocalStack Azure emulator with the lstk CLI:

```bash
# Set the authentication token
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>

# Start the LocalStack Azure emulator
lstk start --type azure

# Route all Azure CLI calls to the LocalStack Azure emulator
lstk az start-interception
```

Navigate to the `terraform` folder:

```bash
cd samples/function-app-storage-http/dotnet/terraform
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

# Check the diagnostic settings of the storage account, of its blob, queue and table services, and of the Log Analytics
# workspace
STORAGE_ACCOUNT_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --query id \
  --output tsv \
  --only-show-errors)
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --workspace-name "$LOG_ANALYTICS_NAME" \
  --query id \
  --output tsv \
  --only-show-errors)

echo -e "\n[$STORAGE_ACCOUNT_NAME] storage account diagnostic settings:\n"
az monitor diagnostic-settings list \
  --resource "$STORAGE_ACCOUNT_ID" \
  --query "[].{Name:name,Metrics:join(', ', metrics[?enabled].category)}" \
  --output table \
  --only-show-errors

for SERVICE in blob queue table; do
  echo -e "\n[$STORAGE_ACCOUNT_NAME] $SERVICE service diagnostic settings:\n"
  az monitor diagnostic-settings list \
    --resource "$STORAGE_ACCOUNT_ID/${SERVICE}Services/default" \
    --query "[].{Name:name,Logs:join(', ', logs[?enabled].category),Metrics:join(', ', metrics[?enabled].category)}" \
    --output table \
    --only-show-errors
done

echo -e "\n[$LOG_ANALYTICS_NAME] Log Analytics workspace diagnostic settings:\n"
az monitor diagnostic-settings list \
  --resource "$LOG_ANALYTICS_ID" \
  --query "[].{Name:name,Logs:join(', ', logs[?enabled].category),Metrics:join(', ', metrics[?enabled].category)}" \
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

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [Azure Functions Methods Documentation](../METHODS.md) - Detailed documentation of all implemented functions
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
