# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning Azure services in LocalStack for Azure. Refer to the [Azure Web App with Managed Identity](../README.md) guide for details about the sample application.

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Terraform](https://developer.hashicorp.com/terraform/downloads): Infrastructure as Code tool for provisioning Azure resources
- [.NET SDK 10.0](https://dotnet.microsoft.com/en-us/download/dotnet/10.0): Required to build and run the ASP.NET Core web application locally
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

The [main.tf](main.tf) Terraform configuration creates the following Azure resources, each through a module in the [modules](modules) folder:

1. [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview): Provides blob storage for persisting vacation activity data. The web application stores each activity as a JSON blob file in the `activities` container.
2. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): Defines the compute resources (CPU, memory, and scaling options) that host the web application.
3. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): Hosts the ASP.NET Core *Vacation Planner* application. The web app uses managed identity to securely access the Azure Storage Account without requiring explicit credentials.
4. [Managed Identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview): Provides secure, credential-free authentication between the web app and storage account. Supports both system-assigned and user-assigned identity types.
5. [Role Assignment](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments): Grants the web app's managed identity the *Storage Blob Data Contributor* role, enabling read/write access to blob containers.
6. [App Service Source Control](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/create-or-update-source-control?view=rest-appservice-2024-11-01): (Optional) Enables continuous deployment from a Git repository for automated application updates.
7. [Log Analytics Workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-workspace-overview): Stores the telemetry of the Application Insights resource, the logs and metrics that the diagnostic settings send to it, and the audit records of the queries run on it.
8. [Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview): A workspace-based resource that collects the requests, the calls to Blob Storage, the log records, the exceptions, the custom events and the custom metric of the web app, which the Microsoft OpenTelemetry Distro sends to the connection string of the `APPLICATIONINSIGHTS_CONNECTION_STRING` app setting.
9. [Diagnostic Settings](https://learn.microsoft.com/en-us/azure/azure-monitor/data-collection/diagnostic-settings): Send the resource logs and the platform metrics of the web app, the platform metrics of the App Service plan and of the storage account, the logs and the transaction metrics of the blob service, and the query audit of the workspace itself to the Log Analytics workspace. The Application Insights resource has none: a workspace-based resource can't send to the workspace it's based on.

The web app allows users to plan and manage vacation activities, storing all activity data as blob files in the `activities` containers in the [Azure Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview). For more information, see [Azure Web App with Managed Identity](../README.md).


## Provisioning Scripts

You can use the [deploy.sh](deploy.sh) script to automate the deployment of all Azure resources and the sample application in a single step, streamlining setup and reducing manual configuration. Before running the script, customize the variable values based on your needs. In particular, use the `MANAGED_IDENTITY_TYPE` variable to specify the type of managed identity to provision: `SystemAssigned` or `UserAssigned`.

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
cd samples/web-app-managed-identity/dotnet/terraform
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
RESOURCE_GROUP_NAME="${PREFIX}-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
CONTAINER_NAME='activities'
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-insights-${SUFFIX}"

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

# Check user-assigned managed identity, which only the deployments with a user-assigned identity create
echo -e "\n[$MANAGED_IDENTITY_NAME] managed identity:\n"
az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,ClientId:clientId,PrincipalId:principalId}' \
	--output table \
	--only-show-errors 2>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$MANAGED_IDENTITY_NAME] managed identity: the web app uses its system-assigned managed identity"
fi

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

# Check Log Analytics workspace
echo -e "\n[$LOG_ANALYTICS_NAME] Log Analytics workspace:\n"
az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,Sku:sku.name,RetentionInDays:retentionInDays}' \
	--output table \
	--only-show-errors

# Check Application Insights component
echo -e "\n[$APPLICATION_INSIGHTS_NAME] Application Insights component:\n"
az monitor app-insights component show \
	--app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,ApplicationType:applicationType,WorkspaceResourceId:workspaceResourceId}' \
	--output table \
	--only-show-errors

# Check the diagnostic settings of the web app and of its App Service plan
WEB_APP_ID=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
APP_SERVICE_PLAN_ID=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query appServicePlanId \
	--output tsv \
	--only-show-errors)

echo -e "\n[$WEB_APP_NAME] web app diagnostic settings:\n"
az monitor diagnostic-settings list \
	--resource "$WEB_APP_ID" \
	--query "[].{Name:name,Logs:join(', ', logs[?enabled].category),Metrics:join(', ', metrics[?enabled].category)}" \
	--output table \
	--only-show-errors

echo -e "\nApp Service plan diagnostic settings:\n"
az monitor diagnostic-settings list \
	--resource "$APP_SERVICE_PLAN_ID" \
	--query "[].{Name:name,Metrics:join(', ', metrics[?enabled].category)}" \
	--output table \
	--only-show-errors

# Check the diagnostic settings of the storage account, of its blob service and of the Log Analytics workspace
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

echo -e "\n[$STORAGE_ACCOUNT_NAME] blob service diagnostic settings:\n"
az monitor diagnostic-settings list \
	--resource "$STORAGE_ACCOUNT_ID/blobServices/default" \
	--query "[].{Name:name,Logs:join(', ', logs[?enabled].category),Metrics:join(', ', metrics[?enabled].category)}" \
	--output table \
	--only-show-errors

echo -e "\n[$LOG_ANALYTICS_NAME] Log Analytics workspace diagnostic settings:\n"
az monitor diagnostic-settings list \
	--resource "$LOG_ANALYTICS_ID" \
	--query "[].{Name:name,Logs:join(', ', logs[?enabled].category),Metrics:join(', ', metrics[?enabled].category)}" \
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

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
