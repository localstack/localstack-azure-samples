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

The [main.tf](main.tf) Terraform module creates the following Azure resources, each through a module of the [modules](modules) folder except the resource group:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): Logical container for all resources in the sample.
2. [Azure SQL Server](https://learn.microsoft.com/en-us/azure/azure-sql/database/sql-database-paas-overview): Logical server hosting one or more Azure SQL Databases.
3. [Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/): The `PlannerDB` database storing relational vacation activity data. Its auditing (`azurerm_mssql_database_extended_auditing_policy`, with `log_monitoring_enabled`) sends the records of the statements run on it and of the sign-ins to the workspace, through its diagnostic setting.
4. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): The compute resource that hosts the web application.
5. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): Hosts the ASP.NET Core Razor Pages single-page application (*Vacation Planner*), connected to Azure SQL Database. The app setting `APPLICATIONINSIGHTS_CONNECTION_STRING` holds the connection string of the Application Insights resource.
6. [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview): Stores the SQL connection string as a secret, a self-signed certificate for HTTPS, and the RSA key that serves as the [TDE protector](https://learn.microsoft.com/en-us/azure/azure-sql/database/transparent-data-encryption-byok-overview) of the SQL server.
7. [User-Assigned Managed Identities](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview): The identity the web app reads the connection string and the certificate from Key Vault with, which holds the Key Vault Secrets User and Key Vault Certificate User roles on the vault, and the identity the SQL server uses to reach its TDE protector key in Key Vault, which holds the Key Vault Crypto Service Encryption User role. The vault uses the [Azure RBAC permission model](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide), and the web app's `AZURE_CLIENT_ID` app setting selects its identity.
8. [Azure Log Analytics Workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-workspace-overview): Stores the telemetry of Application Insights, and the resource logs and platform metrics that the diagnostic settings of the web app, the App Service plan, the database, the key vault and the workspace itself send to it.
9. [Azure Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview): workspace-based, it stores the telemetry of the web app in the Log Analytics workspace.

The system implements a Vacation Planner web application that stores and retrieves activity data from Azure SQL Database. For more information, see [Azure Web App with Azure SQL Database and Azure Key Vault](../README.md).

## Configuration

`providers.tf` hardcodes no endpoint and no subscription. `deploy.sh` exports the variables the [Azure Provider for Terraform](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) reads natively, so the same files run unmodified against the LocalStack emulator and against Azure:

| Variable                               | Exported when                         | Value                                                     |
| -------------------------------------- | ------------------------------------- | --------------------------------------------------------- |
| `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID` | always                                | `az account show`                                         |
| `ARM_METADATA_HOSTNAME`                | the active `az cloud` is `LocalStack` | host of `az cloud show --query endpoints.resourceManager` |

The provider discovers every endpoint of the emulator from `ARM_METADATA_HOSTNAME`, and authenticates with the Azure CLI session on both targets. Against Azure, `deploy.sh` unsets `ARM_METADATA_HOSTNAME`, so the provider uses the endpoints of the public cloud. Running `terraform` directly, rather than through `deploy.sh`, needs these variables exported.

`deploy.sh` also passes the object id and the principal type of the principal that runs it (`deployer_object_id`, `deployer_principal_type`): the configuration grants it the Key Vault Crypto Officer, Secrets Officer and Certificates Officer roles on the vault, because it writes the TDE key, the connection string secret and the certificate through the Key Vault data plane. On Azure a new role assignment takes a while to apply, so the configuration waits `rbac_propagation_delay` (60 seconds by default) after the role assignments on the vault before it uses them; `deploy.sh` passes `0s` on the emulator, which applies them immediately.

## Deployment

You can set up the Azure emulator by utilizing LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/) to obtain your Auth Token and specify it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure). To pull the Azure Docker image, execute the following command:

```bash
docker pull localstack/localstack-azure
```

> [!IMPORTANT]
> Each logical server you create runs a Microsoft SQL Server container, so you must accept the [SQL Server End-User Licensing Agreement](https://go.microsoft.com/fwlink/?LinkId=746388) before the emulator provisions one.
> Start the emulator with `MSSQL_ACCEPT_EULA` set to `Y`:
> 
> ```bash
> LOCALSTACK_MSSQL_ACCEPT_EULA=Y lstk start --type azure
> ```
> 
> Host variables prefixed with `LOCALSTACK_` are forwarded to the emulator, so the container receives `MSSQL_ACCEPT_EULA=Y`.
> 
> To accept it once rather than on every start, add it to an environment profile in your `lstk` config:
> 
> ```toml
> [[containers]]
> type = "azure"
> tag  = "latest"
> port = "4566"
> env  = ["mssql"]
> 
> [env.mssql]
> MSSQL_ACCEPT_EULA = "Y"
> ```
> 
> A profile's values are injected into the container directly, so the `LOCALSTACK_` prefix is not used here.
> `lstk` reads the first `config.toml` it finds, starting with `./.lstk/config.toml` in the current directory and then `$HOME/.config/lstk/config.toml`.
> See [Config file search order](https://docs.localstack.cloud/azure/developer-tools/running-localstack/lstk/configuration/#config-file-search-order) for the full list and [Passing environment variables to the container](https://docs.localstack.cloud/azure/developer-tools/running-localstack/lstk/configuration/#passing-environment-variables-to-the-container) for how profiles work.
> 
> If you start the emulator with the `docker` CLI or Docker Compose, set `MSSQL_ACCEPT_EULA=Y` directly in the container environment instead.
> Without it, `az sql server create` fails with `(EulaNotAccepted)`.

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
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
SQL_SERVER_NAME="${PREFIX}-sqlserver-${SUFFIX}"
SQL_DATABASE_NAME='PlannerDB'
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
KEY_VAULT_NAME="${PREFIX}-kv-${SUFFIX}"
SECRET_NAME="${PREFIX}-secret-${SUFFIX}"
TDE_KEY_NAME="${PREFIX}-tde-key-${SUFFIX}"
SQL_SERVER_IDENTITY_NAME="${PREFIX}-tde-identity-${SUFFIX}"
WEB_APP_IDENTITY_NAME="${PREFIX}-webapp-identity-${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-insights-${SUFFIX}"

# Exit with an error unless a principal holds a role on the key vault.
# $1: the principal (object) id
# $2: the role name
# $3: the description of the principal, used in messages
require_key_vault_role() {
	local count
	count=$(az role assignment list \
		--assignee "$1" \
		--scope "$KEY_VAULT_ID" \
		--query "length([?roleDefinitionName=='$2'])" \
		--output tsv \
		--only-show-errors)

	if [[ $count -ge 1 ]]; then
		echo "The $3 holds the [$2] role on the [$KEY_VAULT_NAME] key vault"
	else
		echo "The $3 does not hold the [$2] role on the [$KEY_VAULT_NAME] key vault"
		exit 1
	fi
}

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

# Check that the Key Vault key is the TDE protector of the Azure SQL Server
echo -e "\n[$SQL_SERVER_NAME] SQL server TDE protector:\n"
# Read the key through Azure Resource Manager: the Bicep variant grants the caller no Key Vault data-plane access.
KEY_VAULT_ID=$(az keyvault show \
--name "$KEY_VAULT_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "id" \
--output tsv)
TDE_KEY_ID=$(az resource show \
--ids "$KEY_VAULT_ID/keys/$TDE_KEY_NAME" \
--api-version 2024-11-01 \
--query "properties.keyUriWithVersion" \
--output tsv)
TDE_PROTECTOR=$(az sql server tde-key show \
--server "$SQL_SERVER_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--output json)
echo "$TDE_PROTECTOR" | jq '{serverKeyType, uri, autoRotationEnabled}'
if [[ "$(jq -r .serverKeyType <<< "$TDE_PROTECTOR")" != "AzureKeyVault" ||
	"$(jq -r .uri <<< "$TDE_PROTECTOR")" != "$TDE_KEY_ID" ||
	"$(jq -r .autoRotationEnabled <<< "$TDE_PROTECTOR")" != "true" ]]; then
	echo "The TDE protector of [$SQL_SERVER_NAME] is not the auto-rotated Key Vault key [$TDE_KEY_ID]"
	exit 1
fi

# Check that TDE is enabled on the Azure SQL Database
TDE_STATE=$(az sql db tde show \
--database "$SQL_DATABASE_NAME" \
--server "$SQL_SERVER_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "state" \
--output tsv)
echo -e "\n[$SQL_DATABASE_NAME] SQL database TDE state: [$TDE_STATE]"
if [[ "$TDE_STATE" != "Enabled" ]]; then
	echo "TDE is not enabled on [$SQL_DATABASE_NAME]"
	exit 1
fi

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

# Check that the key vault uses the Azure RBAC permission model: the role assignments below only work on such a vault
KEY_VAULT_RBAC=$(az keyvault show \
--name "$KEY_VAULT_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "properties.enableRbacAuthorization" \
--output tsv)
echo -e "\n[$KEY_VAULT_NAME] Key Vault RBAC authorization: [$KEY_VAULT_RBAC]"
if [[ $KEY_VAULT_RBAC != "true" ]]; then
	echo "The [$KEY_VAULT_NAME] key vault does not use the Azure RBAC permission model"
	exit 1
fi

# Check that the web app runs with its user-assigned managed identity, which AZURE_CLIENT_ID selects in the app
echo -e "\n[$WEB_APP_IDENTITY_NAME] managed identity of the [$WEB_APP_NAME] web app:\n"
# tr drops the carriage return the Azure CLI ends each line with on Windows: mapfile keeps it, even with bash's igncr option
mapfile -t WEB_APP_IDENTITY_FIELDS < <(az identity show \
--name "$WEB_APP_IDENTITY_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "[id, clientId, principalId]" \
--output tsv | tr -d '\r')
WEB_APP_IDENTITY_ID="${WEB_APP_IDENTITY_FIELDS[0]:-}"
WEB_APP_IDENTITY_CLIENT_ID="${WEB_APP_IDENTITY_FIELDS[1]:-}"
WEB_APP_IDENTITY_PRINCIPAL_ID="${WEB_APP_IDENTITY_FIELDS[2]:-}"
if [[ -z $WEB_APP_IDENTITY_ID || -z $WEB_APP_IDENTITY_CLIENT_ID || -z $WEB_APP_IDENTITY_PRINCIPAL_ID ]]; then
	echo "Failed to retrieve the [$WEB_APP_IDENTITY_NAME] managed identity"
	exit 1
fi
if az webapp identity show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "keys(userAssignedIdentities || \`{}\`)" \
	--output tsv | tr -d '\r' | grep -q -i -x -F "$WEB_APP_IDENTITY_ID"; then
	echo "The [$WEB_APP_NAME] web app uses the [$WEB_APP_IDENTITY_NAME] managed identity"
else
	echo "The [$WEB_APP_NAME] web app does not use the [$WEB_APP_IDENTITY_NAME] managed identity"
	exit 1
fi
AZURE_CLIENT_ID_SETTING=$(az webapp config appsettings list \
--name "$WEB_APP_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "[?name=='AZURE_CLIENT_ID'].value | [0]" \
--output tsv)
if [[ $AZURE_CLIENT_ID_SETTING == "$WEB_APP_IDENTITY_CLIENT_ID" ]]; then
	echo "The AZURE_CLIENT_ID app setting holds the client id of the [$WEB_APP_IDENTITY_NAME] managed identity"
else
	echo "The AZURE_CLIENT_ID app setting [$AZURE_CLIENT_ID_SETTING] is not the client id [$WEB_APP_IDENTITY_CLIENT_ID] of the [$WEB_APP_IDENTITY_NAME] managed identity"
	exit 1
fi

# Check the roles of the managed identities on the key vault: the web app reads the connection string and the private
# key of its certificate as secrets, and the certificate itself; the SQL server wraps and unwraps its database
# encryption keys with the TDE protector key
echo -e "\n[$KEY_VAULT_NAME] Key Vault role assignments:\n"
SQL_SERVER_IDENTITY_PRINCIPAL_ID=$(az identity show \
--name "$SQL_SERVER_IDENTITY_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "principalId" \
--output tsv)
if [[ -z $SQL_SERVER_IDENTITY_PRINCIPAL_ID ]]; then
	echo "Failed to retrieve the principalId of the [$SQL_SERVER_IDENTITY_NAME] managed identity"
	exit 1
fi
require_key_vault_role "$WEB_APP_IDENTITY_PRINCIPAL_ID" "Key Vault Secrets User" "[$WEB_APP_IDENTITY_NAME] managed identity"
require_key_vault_role "$WEB_APP_IDENTITY_PRINCIPAL_ID" "Key Vault Certificate User" "[$WEB_APP_IDENTITY_NAME] managed identity"
require_key_vault_role "$SQL_SERVER_IDENTITY_PRINCIPAL_ID" "Key Vault Crypto Service Encryption User" "[$SQL_SERVER_IDENTITY_NAME] managed identity"

# Check Application Insights component
echo -e "\n[$APPLICATION_INSIGHTS_NAME] Application Insights component:\n"
az monitor app-insights component show \
	--app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,ApplicationType:applicationType,WorkspaceResourceId:workspaceResourceId}' \
	--output table \
	--only-show-errors

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

## Telemetry, logs and metrics

Once the web app is deployed, read the telemetry it sent to Application Insights and the logs and metrics the diagnostic settings sent to the workspace. The scripts take the same `PREFIX` and `SUFFIX` as the deployment:

```bash
bash ../scripts/query-telemetry.sh
bash ../scripts/query-logs-and-metrics.sh
```

See [Application Insights](../README.md#application-insights) and [Logs and metrics](../README.md#logs-and-metrics) for what they read.

## Related Documentation

- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
