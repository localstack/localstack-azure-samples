# Bicep Deployment

This directory contains the Bicep template and a deployment script for provisioning Azure services in LocalStack for Azure. Refer to the [Azure Web App with Azure SQL Database](../README.md) guide for details about the sample application.

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep): VS Code extension for Bicep language support and IntelliSense
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [Python](https://www.python.org/downloads/): Python runtime (version 3.12 or above)
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The deployment script uses the `azlocal` CLI instead of the standard Azure CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

The Bicep template deploys the following Azure resources:

1. [Azure SQL Server](https://learn.microsoft.com/en-us/azure/azure-sql/database/sql-database-paas-overview): Logical server hosting one or more Azure SQL Databases.
2. [Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/): The `PlannerDB` database storing relational vacation activity data.
3. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): The compute resource that hosts the web application.
4. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): Hosts the Python Flask single-page application (*Vacation Planner*), connected to Azure SQL Database.
5. [App Service Source Control](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/create-or-update-source-control?view=rest-appservice-2024-11-01): (Optional) Configures automatic deployment from a public GitHub repository.

The web app allows users to plan and manage vacation activities, storing all activity data in the `Activities` table in the `PlannerDB` database. For more information, see [Azure Web App with Azure SQL Database](../README.md).

## Bicep Templates

The `main.bicep` Bicep template defines all Azure resources using declarative syntax:

```bicep
@description('Specifies the prefix for the name of the Azure resources.')
@minLength(2)
param prefix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the suffix for the name of the Azure resources.')
@minLength(2)
param suffix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('Specifies the tier name for the hosting plan.')
@allowed([
  'Basic'
  'Standard'
  'ElasticPremium'
  'Premium'
  'PremiumV2'
  'Premium0V3'
  'PremiumV3'
  'PremiumMV3'
  'Isolated'
  'IsolatedV2'
  'WorkflowStandard'
  'FlexConsumption'
])
param skuTier string = 'Standard'

@description('Specifies the SKU name for the hosting plan.')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'EP1'
  'EP2'
  'EP3'
  'P1'
  'P2'
  'P3'
  'P1V2'
  'P2V2'
  'P3V2'
  'P0V3'
  'P1V3'
  'P2V3'
  'P3V3'
  'P1MV3'
  'P2MV3'
  'P3MV3'
  'P4MV3'
  'P5MV3'
  'I1'
  'I2'
  'I3'
  'I1V2'
  'I2V2'
  'I3V2'
  'I4V2'
  'I5V2'
  'I6V2'
  'WS1'
  'WS2'
  'WS3'
  'FC1'
])
param skuName string = 'S1'

@description('Specifies the kind of the hosting plan.')
@allowed([
  'app'
  'elastic'
  'functionapp'
  'windows'
  'linux'
])
param appServicePlanKind string = 'linux'

@description('Specifies whether the hosting plan is reserved.')
param reserved bool = true

@description('Specifies whether the hosting plan is zone redundant.')
param appServicePlanZoneRedundant bool = false

@description('Specifies the language runtime used by the Azure Web App.')
@allowed([
  'dotnet'
  'dotnet-isolated'
  'python'
  'java'
  'node'
  'powerShell'
  'custom'
])
param runtimeName string

@description('Specifies the target language version used by the Azure Web App.')
param runtimeVersion string

@description('Specifies the kind of the hosting plan.')
@allowed([
  'app'                                    // Windows Web app
  'app,linux'                              // Linux Web app
  'app,linux,container'                    // Linux Container Web app
  'hyperV'                                 // Windows Container Web App
  'app,container,windows'                  // Windows Container Web App
  'app,linux,kubernetes'                   // Linux Web App on ARC
  'app,linux,container,kubernetes'         // Linux Container Web App on ARC
  'functionapp'                            // Function Code App
  'functionapp,linux'                      // Linux Consumption Function app
  'functionapp,linux,container,kubernetes' // Function Container App on ARC
  'functionapp,linux,kubernetes'           // Function Code App on ARC
])
param webAppKind string = 'app,linux'

@description('Specifies whether HTTPS is enforced for the Azure Web App.')
param httpsOnly bool = false

@description('Specifies the minimum TLS version for the Azure Web App.')
@allowed([
  '1.0'
  '1.1'
  '1.2'
  '1.3'
])
param minTlsVersion string = '1.2'

@description('Specifies whether the public network access is enabled or disabled')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Specifies the optional Git Repo URL.')
param repoUrl string = ''

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

@description('Specifies the administrator username of the SQL logical server.')
param administratorLogin string = 'sqladmin'

@description('Specifies the administrator password of the SQL logical server.')
@secure()
param administratorLoginPassword string = 'P@ssw0rd1234!'

@description('Conditional. The Azure Active Directory (AAD) administrator authentication. Required if no `administratorLogin` & `administratorLoginPassword` is provided.')
param administrators object?

@description('Specifies the conditional Developmentresource ID of a user-assigned identityDevelopment to be used by default. This is required if `userAssignedIdentities` is not empty.')
param primaryUserAssignedIdentityResourceId string?

@allowed([
  '1.0'
  '1.1'
  '1.2'
  '1.3'
])
@description('Specifies the optional Developmentminimal TLS versionDevelopment allowed for connections.')
param minimalTlsVersion string = '1.2'

@allowed([
  'Disabled'
  'Enabled'
])
@description('Specifies whether or not to optionally enable IPv6 support for this server.')
param isIPv6Enabled string = 'Disabled'

@description('Specifies the version of the SQL server to deploy.')
param version string = '12.0'

@description('Specifies whether to optionally restrict outbound network access for this server.')
@allowed([
  'Enabled'
  'Disabled'
])
param restrictOutboundNetworkAccess string?

@description('Specifies the name of the SQL Database.')
param sqlDatabaseName string = 'PlannerDB'

@description('Specifies the optional SKU for the database.')
param sku object = {
  name: 'Standard'
  tier: 'Standard'
  capacity: 10
}

@description('Specifies the optional time in minutes after which the database automatically pauses. A value of -1 disables automatic pausing.')
param autoPauseDelay int = -1

@description('Specifies the required Developmentavailability zoneDevelopment. A value of 1, 2, or 3 hardcodes the zone; -1 defines no zone. Note that these are logical availability zones within your Azure subscription. Refer to the Azure documentation for the mapping between physical and logical zones.')
@allowed([
  -1
  1
  2
  3
])
param availabilityZone int = -1

@description('Specifies the optional collation for the metadata catalog.')
param catalogCollation string = 'DATABASE_DEFAULT'

@description('Specifies the optional collation for the database.')
param collation string = 'SQL_Latin1_General_CP1_CI_AS'

@description('Specifies the optional mode used for database creation.')
param createMode
  | 'Default'
  | 'Copy'
  | 'OnlineSecondary'
  | 'PointInTimeRestore'
  | 'Recovery'
  | 'Restore'
  | 'RestoreExternalBackup'
  | 'RestoreExternalBackupSecondary'
  | 'RestoreLongTermRetentionBackup'
  | 'Secondary' = 'Default'

@description('Specifies the optional resource ID of the elastic pool containing this database.')
param elasticPoolResourceId string?

@description('Specifies the optional Client ID for cross-tenant per-database Customer-Managed Key (CMK) scenarios.')
@minLength(36)
@maxLength(36)
param federatedClientId string?

@description('Specifies the optional behavior when monthly free limits are exhausted for a free database.')
param freeLimitExhaustionBehavior 'AutoPause' | 'BillOverUsage'?

@description('Specifies the optional number of read-only secondary replicas associated with the database.')
param highAvailabilityReplicaCount int = 0

@description('Specifies whether or not this database is a Developmentledger databaseDevelopment. All tables will be ledger tables. Note: this value cannot be changed after database creation.')
param isLedgerOn bool = false

@description('Specifies the optional license type to apply for this database.')
param licenseType 'BasePrice' | 'LicenseIncluded'?

@description('Specifies the optional resource identifier of the long-term retention backup used for the create operation.')
param longTermRetentionBackupResourceId string?

@description('Specifies the optional Maintenance Configuration ID assigned to the database, which defines the period for maintenance updates.')
param maintenanceConfigurationId string?

@description('Specifies whether optional customer-controlled manual cutover is required during an Update Database operation to the Hyperscale tier.')
param manualCutover bool?

@description('Specifies the optional minimal capacity (vCores) that the database will always have allocated.')
param minCapacity string = '0'

@description('Specifies the optional trigger for a customer-controlled manual cutover during a wait state while a scaling operation is in progress.')
param performCutover bool?

@description('Specifies the optional type of enclave requested for the database, either Default or VBS enclaves.')
param preferredEnclaveType 'Default' | 'VBS'?

@description('Specifies the optional state of read-only routing.')
param readScale 'Enabled' | 'Disabled' = 'Disabled'

@description('Specifies the optional resource identifier of the recoverable database associated with the create operation.')
param recoverableDatabaseResourceId string?

@description('Specifies the optional resource identifier of the recovery point associated with the create operation.')
param recoveryServicesRecoveryPointResourceId string?

@description('Specifies the optional storage account type to be used for storing database backups.')
param requestedBackupStorageRedundancy 'Geo' | 'GeoZone' | 'Local' | 'Zone' = 'Local'

@description('Specifies the optional resource identifier of the restorable dropped database associated with the create operation.')
param restorableDroppedDatabaseResourceId string?

@description('Specifies the optional point in time (ISO8601 format) of the source database to restore when `createMode` is set to `Restore` or `PointInTimeRestore`.')
param restorePointInTime string?

@description('Specifies the optional name of the sample schema to apply when creating this database.')
param sampleName string = ''

@description('Specifies the optional secondary type of the database, if it is a secondary.')
param secondaryType 'Geo' | 'Named' | 'Standby'?

@description('Specifies the optional time the database was deleted when restoring a deleted database.')
param sourceDatabaseDeletionDate string?

@description('Specifies the optional resource identifier of the source database associated with the create operation.')
param sourceDatabaseResourceId string?

@description('Specifies the optional resource identifier of the source associated with the create operation of this database.')
param sourceResourceId string?

@description('Specifies whether or not the database uses free monthly limits. This is allowed for only one database per subscription.')
param useFreeLimit bool?

@description('Specifies whether or not this database is Developmentzone redundantDevelopment.')
param sqlDatabaseZoneRedundant bool = false

@description('Specifies the username for the SQL Database.')
param sqlDatabaseUsername string = 'testuser'

@description('Specifies the password for the SQL Database.')
@secure()
param sqlDatabasePassword string = 'TestP@ssw0rd123'

@description('Specifies the required name of the Server Firewall Rule.')
param sqlFirewallRuleName string = 'AllowAllIPs'

@description('Specifies the optional end IP address of the firewall rule. Must be in IPv4 format and greater than or equal to `startIpAddress`. Use \'0.0.0.0\' to allow all Azure-internal IP addresses.')
param endIpAddress string = '255.255.255.255'

@description('Specifies the optional start IP address of the firewall rule. Must be in IPv4 format. Use \'0.0.0.0\' to allow all Azure-internal IP addresses.')
param startIpAddress string = '0.0.0.0'

@description('Specifies the username for the application.')
param username string = 'paolo'

var sqlServerName = '${prefix}-sqlserver-${suffix}'
var webAppName = '${prefix}-webapp-${suffix}'
var appServicePlanName = '${prefix}-app-service-plan-${suffix}'
var identity = {
    type: 'SystemAssigned'
  }

resource sqlServer 'Microsoft.Sql/servers@2024-05-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  identity: identity
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    administrators: union({ administratorType: 'ActiveDirectory' }, administrators ?? {})
    federatedClientId: federatedClientId
    isIPv6Enabled: isIPv6Enabled
    version: version
    minimalTlsVersion: minimalTlsVersion
    primaryUserAssignedIdentityId: primaryUserAssignedIdentityResourceId
    publicNetworkAccess: publicNetworkAccess
    restrictOutboundNetworkAccess: restrictOutboundNetworkAccess
  }
}

resource firewallRule 'Microsoft.Sql/servers/firewallRules@2024-11-01-preview' = {
  name: sqlFirewallRuleName
  parent: sqlServer
  properties: {
    endIpAddress: endIpAddress
    startIpAddress: startIpAddress
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2024-11-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: sku
  properties: {
    autoPauseDelay: autoPauseDelay
    availabilityZone: availabilityZone != -1 ? string(availabilityZone) : 'NoPreference'
    catalogCollation: catalogCollation
    collation: collation
    createMode: createMode
    elasticPoolId: elasticPoolResourceId
    federatedClientId: federatedClientId
    freeLimitExhaustionBehavior: freeLimitExhaustionBehavior
    highAvailabilityReplicaCount: highAvailabilityReplicaCount
    isLedgerOn: isLedgerOn
    licenseType: licenseType
    longTermRetentionBackupResourceId: longTermRetentionBackupResourceId
    maintenanceConfigurationId: maintenanceConfigurationId
    manualCutover: manualCutover
    minCapacity: !empty(minCapacity) ? json(minCapacity) : 0
    performCutover: performCutover
    preferredEnclaveType: preferredEnclaveType
    readScale: readScale
    recoverableDatabaseId: recoverableDatabaseResourceId
    recoveryServicesRecoveryPointId: recoveryServicesRecoveryPointResourceId
    requestedBackupStorageRedundancy: requestedBackupStorageRedundancy
    restorableDroppedDatabaseId: restorableDroppedDatabaseResourceId
    restorePointInTime: restorePointInTime
    sampleName: sampleName
    secondaryType: secondaryType
    sourceDatabaseDeletionDate: sourceDatabaseDeletionDate
    sourceDatabaseId: sourceDatabaseResourceId
    sourceResourceId: sourceResourceId
    useFreeLimit: useFreeLimit
    zoneRedundant: sqlDatabaseZoneRedundant
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  kind: appServicePlanKind
  sku: {
    tier: skuTier
    name: skuName
  }
  properties: {
    reserved: reserved
    zoneRedundant: appServicePlanZoneRedundant
     maximumElasticWorkerCount: skuTier == 'FlexConsumption' ? 1 : 20
  }
}

resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: webAppName
  location: location
  tags: tags
  kind: webAppKind
  properties: {
    httpsOnly: httpsOnly
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: toUpper('${runtimeName}|${runtimeVersion}')
      minTlsVersion: minTlsVersion
      publicNetworkAccess: publicNetworkAccess
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource configAppSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: webApp
  name: 'appsettings'
  properties: {
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    ENABLE_ORYX_BUILD: 'true'
    SQL_SERVER: sqlServer.properties.fullyQualifiedDomainName
    SQL_DATABASE: sqlDatabaseName
    SQL_USERNAME: sqlDatabaseUsername
    SQL_PASSWORD: sqlDatabasePassword
    LOGIN_NAME: username
  }
}

resource webAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2024-11-01' = if (contains(repoUrl,'http')){
  name: 'web'
  parent: webApp
  properties: {
    repoUrl: repoUrl
    branch: 'master'
    isManualIntegration: true
  }
}

output appServicePlanName string = appServicePlan.name
output webAppName string = webApp.name
output webAppUrl string = webApp.properties.defaultHostName
output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
```
## Configuration

Before deploying the `main.bicep` template, update the `bicep.bicepparam` file with your specific values:

```bicep
using 'main.bicep'

param prefix = 'local'
param suffix = 'test'
param runtimeName = 'python'
param runtimeVersion = '3.13'
param username = 'paolo'
```

## Deployment Script

You can use the `deploy.sh` script to automate the deployment of all Azure resources and the sample application in a single step, streamlining setup and reducing manual configuration.

```bash
#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
RESOURCE_GROUP_NAME="$PREFIX-rg"
LOCATION="westeurope"
VALIDATE_TEMPLATE=1
USE_WHAT_IF=0
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
ADMIN_USER='sqladmin'
ADMIN_PASSWORD='P@ssw0rd1234!'
DATABASE_USER_NAME='testuser'
DATABASE_USER_PASSWORD='TestP@ssw0rd123'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"
ENVIRONMENT=$(az account show --query environmentName --output tsv)
DEPLOY_APP=1

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	AZ="azlocal"
else
	echo "Using standard az for AzureCloud environment."
	AZ="az"
fi

# Validates if the resource group exists in the subscription, if not creates it
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
$AZ group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	# Create the resource group
	$AZ group create \
		--name $RESOURCE_GROUP_NAME \
		--location $LOCATION \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created in the subscription [$SUBSCRIPTION_NAME]"
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]"
		exit
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists in the subscription [$SUBSCRIPTION_NAME]"
fi

# Validates the Bicep template
if [[ $VALIDATE_TEMPLATE == 1 ]]; then
	if [[ $USE_WHAT_IF == 1 ]]; then
		# Execute a deployment What-If operation at resource group scope.
		echo "Previewing changes deployed by Bicep template [$TEMPLATE]..."
		$AZ deployment group what-if \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $TEMPLATE \
			--parameters $PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			administratorLogin=$ADMIN_USER \
			administratorLoginPassword=$ADMIN_PASSWORD \
			sqlDatabaseUsername=$DATABASE_USER_NAME \
			sqlDatabasePassword=$DATABASE_USER_PASSWORD \
			--only-show-errors

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			exit
		fi
	else
		# Validate the Bicep template
		echo "Validating Bicep template [$TEMPLATE]..."
		output=$($AZ deployment group validate \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $TEMPLATE \
			--parameters $PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			administratorLogin=$ADMIN_USER \
			administratorLoginPassword=$ADMIN_PASSWORD \
			sqlDatabaseUsername=$DATABASE_USER_NAME \
			sqlDatabasePassword=$DATABASE_USER_PASSWORD \
			--only-show-errors)

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			echo "$output"
			exit
		fi
	fi
fi

# Deploy the Bicep template
echo "Deploying Bicep template [$TEMPLATE]..."
if DEPLOYMENT_OUTPUTS=$($AZ deployment group create \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors \
	--template-file $TEMPLATE \
	--parameters $PARAMETERS \
	--parameters location=$LOCATION \
	prefix=$PREFIX \
	suffix=$SUFFIX \
	administratorLogin=$ADMIN_USER \
	administratorLoginPassword=$ADMIN_PASSWORD \
	sqlDatabaseUsername=$DATABASE_USER_NAME \
	sqlDatabasePassword=$DATABASE_USER_PASSWORD \
	--query 'properties.outputs' -o json); then
	echo "Bicep template [$TEMPLATE] deployed successfully. Outputs:"
	echo "$DEPLOYMENT_OUTPUTS" | jq .
	APP_SERVICE_PLAN_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.appServicePlanName.value')
	WEB_APP_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.webAppName.value')
	SQL_SERVER_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.sqlServerName.value')
	SQL_DATABASE_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.sqlDatabaseName.value')
	echo "Deployment details:"
	echo "appServicePlanName: $APP_SERVICE_PLAN_NAME"
	echo "webAppName: $WEB_APP_NAME"
	echo "webAppUrl: $WEB_APP_URL"
	echo "sqlServerName: $SQL_SERVER_NAME"
	echo "sqlDatabaseName: $SQL_DATABASE_NAME"
else
	echo "Failed to deploy Bicep template [$TEMPLATE]"
	exit 1
fi

if [[ -z "$WEB_APP_NAME" || -z "$SQL_SERVER_NAME" || -z "$SQL_DATABASE_NAME" ]]; then
	echo "Web App Name, SQL Server Name, or SQL Database Name is empty. Exiting."
	exit 1
fi

# Retrieve the fullyQualifiedDomainName of the SQL server
echo "Retrieving the fullyQualifiedDomainName of the [$SQL_SERVER_NAME] SQL server..."
SQL_SERVER_FQDN=$($AZ sql server show \
	--name "$SQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "fullyQualifiedDomainName" \
	--output tsv)

if [ -z "$SQL_SERVER_FQDN" ]; then
	echo "Failed to retrieve the fullyQualifiedDomainName of the SQL server"
	exit 1
fi

# Create server-level login
echo "Creating login [$DATABASE_USER_NAME] at server level..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d master \
	-U "$ADMIN_USER" \
	-P "$ADMIN_PASSWORD" \
	-Q "IF NOT EXISTS (SELECT * FROM sys.sql_logins WHERE name = '$DATABASE_USER_NAME') 
			CREATE LOGIN [$DATABASE_USER_NAME] WITH PASSWORD = '$DATABASE_USER_PASSWORD';" \
	-V 1

if [ $? -eq 0 ]; then
	echo "Login [$DATABASE_USER_NAME] created successfully"
else
	echo "Failed to create login [$DATABASE_USER_NAME]"
	exit 1
fi

# Create database user
echo "Creating user [$DATABASE_USER_NAME] in database [$SQL_DATABASE_NAME]..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d "$SQL_DATABASE_NAME" \
	-U "$ADMIN_USER" \
	-P "$ADMIN_PASSWORD" \
	-Q "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$DATABASE_USER_NAME') 
      CREATE USER [$DATABASE_USER_NAME] FOR LOGIN [$DATABASE_USER_NAME];" \
	-V 1

if [ $? -eq 0 ]; then
	echo "User [$DATABASE_USER_NAME] created successfully in database [$SQL_DATABASE_NAME]"
else
	echo "Failed to create user [$DATABASE_USER_NAME]"
	exit 1
fi

# Grant permissions including DDL rights
echo "Granting permissions to [$DATABASE_USER_NAME]..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d "$SQL_DATABASE_NAME" \
	-U "$ADMIN_USER" \
	-P "$ADMIN_PASSWORD" \
	-Q "ALTER ROLE db_datareader ADD MEMBER [$DATABASE_USER_NAME]; 
			ALTER ROLE db_datawriter ADD MEMBER [$DATABASE_USER_NAME];
			ALTER ROLE db_ddladmin ADD MEMBER [$DATABASE_USER_NAME];" \
	-V 1

if [ $? -eq 0 ]; then
	echo "Permissions granted successfully to [$DATABASE_USER_NAME]"
else
	echo "Failed to grant permissions to [$DATABASE_USER_NAME]"
	exit 1
fi

# Test connection
echo "Testing connection with user [$DATABASE_USER_NAME]..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d "$SQL_DATABASE_NAME" \
	-U "$DATABASE_USER_NAME" \
	-P "$DATABASE_USER_PASSWORD" \
	-Q "SELECT SYSTEM_USER AS CurrentUser, DB_NAME() AS CurrentDatabase, GETDATE() AS CurrentTime;" \
	-V 1

if [ $? -eq 0 ]; then
	echo "Connection test successful with user [$DATABASE_USER_NAME]"
else
	echo "Connection test failed with user [$DATABASE_USER_NAME]"
	exit 1
fi

# Create table
echo "Creating test [Products] table..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d "$SQL_DATABASE_NAME" \
	-U "$DATABASE_USER_NAME" \
	-P "$DATABASE_USER_PASSWORD" \
	-Q "IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Activities' AND schema_id = SCHEMA_ID('dbo'))
		CREATE TABLE dbo.Activities (
			-- Primary Key: UNIQUEIDENTIFIER with a default of a new sequential GUID (best for indexing)
			id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWSEQUENTIALID(),

			-- Username field
			username VARCHAR(32) NOT NULL,

			-- Description of the activity
			activity VARCHAR(128) NOT NULL,

			-- Timestamp of the activity
			timestamp DATETIME NOT NULL
		);" \
	-V 1

if [ $? -eq 0 ]; then
	echo "Test [Activities] table created successfully"
else
	echo "Failed to create test [Activities] table"
	exit 1
fi

# Insert data
echo "Inserting test data into [Activities] table..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d "$SQL_DATABASE_NAME" \
	-U "$DATABASE_USER_NAME" \
	-P "$DATABASE_USER_PASSWORD" \
	-Q "INSERT INTO Activities (username, activity, timestamp) 
			VALUES 
			('paolo', 'Go to Paris', GETDATE()),
			('paolo', 'Go to London', GETDATE()),
			('paolo', 'Go to Mexico', GETDATE());" \
	-V 1

if [ $? -eq 0 ]; then
	echo "Test data inserted successfully into [Activities] table"
else
	echo "Failed to insert test data into [Activities] table"
	exit 1
fi

# Query data
echo "Querying test data from [Activities] table..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d "$SQL_DATABASE_NAME" \
	-U "$DATABASE_USER_NAME" \
	-P "$DATABASE_USER_PASSWORD" \
	-Q "SELECT * FROM Activities;" \
	-V 1

if [ $? -eq 0 ]; then
	echo "Test data queried successfully from [Activities] table"
else
	echo "Failed to query test data from [Activities] table"
	exit 1
fi

if [[ $DEPLOY_APP -eq 0 ]]; then
	echo "Skipping web app deployment as DEPLOY_APP flag is set to 0."
	exit 0
fi

# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py activities.py database.py static templates requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
$AZ webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app [$WEB_APP_NAME] created successfully."
else
	echo "Failed to create web app [$WEB_APP_NAME]."
	exit 1
fi

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi
```

> **Note**  
> You can use the `azlocal` CLI as a drop-in replacement for the `az` CLI to direct all commands to the LocalStack for Azure emulator. Alternatively, run `azlocal start_interception` to automatically intercept and redirect all `az` commands to LocalStack. For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

The `deploy.sh` script executes the following steps:

- Specifies the variables used during deployment.
- Creates the resource group if it does not exist.
- Conditionally validates the `main.bicep` module to check its syntax is correct and all parameters make sense.
- Conditionally runs a what-if deployment to execute a dry run to preview the resources that will be created, updated, or deleted.
- Runs the `main.bicep` template to create all the Azure resources.
- Collects important information from the deployment (like resource names) for later use.
- Uses jq (a JSON tool) to extract the names of resources we just created.
- Shows us all the settings that got applied to the Web App.
- Removes previous build artifacts for consistency.
- Creates zip archive in format expected by Web App.
- Uploads pre-built application package to the newly created Web App.

> **Note**  
> Azure CLI commands use `--verbose` argument to print execution details and the `--debug` flag to show low-level REST calls for debugging. For more information, see [Get started with Azure CLI](https://learn.microsoft.com/en-us/cli/azure/get-started-with-azure-cli)

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

Navigate to the `bicep` folder:

```bash
cd samples/web-app-sql-database/python/bicep
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

# Check Azure Web App
$AZ webapp show \
--name local-webapp-test \
--resource-group local-rg \
--output table

# Check Azure SQL Server
$AZ sql server show \
--name local-sqlserver-test \
--resource-group local-rg \
--output table

# Check Azure SQL Database
$AZ sql db show \
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

- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Bicep Language Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)