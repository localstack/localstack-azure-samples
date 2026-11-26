#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
SQL_SERVER_NAME="${PREFIX}-sqlserver-${SUFFIX}"
SQL_SERVER_IDENTITY_NAME="${PREFIX}-tde-identity-${SUFFIX}"
FIREWALL_RULE_NAME="AllowAllIPs"
ADMIN_USER='sqladmin'
ADMIN_PASSWORD='P@ssw0rd1234!'
DATABASE_USER_NAME='testuser'
DATABASE_USER_PASSWORD='TestP@ssw0rd123'
SQL_DATABASE_NAME='PlannerDB'
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="S1"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
LOGIN_NAME="Paolo"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"
RUNTIME="dotnetcore"
RUNTIME_VERSION="10.0"
DEPLOY_APP=1
KEY_VAULT_NAME="${PREFIX}-kv-${SUFFIX}"
SECRET_NAME="${PREFIX}-secret-${SUFFIX}"
CERT_NAME="${PREFIX}-cert-${SUFFIX}"
TDE_KEY_NAME="${PREFIX}-tde-key-${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-insights-${SUFFIX}"
DIAGNOSTIC_SETTINGS_NAME='default'
WEB_APP_IDENTITY_NAME="${PREFIX}-webapp-identity-${SUFFIX}"
KEY_VAULT_SECRETS_USER_ROLE="Key Vault Secrets User"
KEY_VAULT_CERTIFICATE_USER_ROLE="Key Vault Certificate User"
KEY_VAULT_CRYPTO_SERVICE_ENCRYPTION_USER_ROLE="Key Vault Crypto Service Encryption User"
KEY_VAULT_SECRETS_OFFICER_ROLE="Key Vault Secrets Officer"
KEY_VAULT_CERTIFICATES_OFFICER_ROLE="Key Vault Certificates Officer"
KEY_VAULT_CRYPTO_OFFICER_ROLE="Key Vault Crypto Officer"
ROLE_ASSIGNMENT_RETRY_COUNT=3
ROLE_ASSIGNMENT_RETRY_SLEEP=5
KEY_VAULT_RETRY_COUNT=20
KEY_VAULT_RETRY_SLEEP=30

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Assign a role to a principal at a scope, unless the assignment already exists. The assignee is given as an
# object id together with its principal type, so no directory lookup happens at creation time.
# $1: the object id of the principal
# $2: the principal type (ServicePrincipal, User or Group)
# $3: the role name
# $4: the scope (resource id)
# $5: the description of the principal, used in messages
# $6: the description of the scope, used in messages
ensure_role_assignment() {
	local principal_id=$1
	local principal_type=$2
	local role=$3
	local scope=$4
	local principal_description=$5
	local scope_description=$6
	local current attempt

	echo "Checking if the $principal_description has the [$role] role assignment on the $scope_description..."
	current=$(az role assignment list \
		--assignee "$principal_id" \
		--scope "$scope" \
		--query "[?roleDefinitionName=='$role'].roleDefinitionName" \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ $current == "$role" ]]; then
		echo "The $principal_description already has the [$role] role assignment on the $scope_description"
		return 0
	fi

	echo "Assigning the [$role] role to the $principal_description on the $scope_description..."
	for attempt in $(seq 1 "$ROLE_ASSIGNMENT_RETRY_COUNT"); do
		if az role assignment create \
			--assignee-object-id "$principal_id" \
			--assignee-principal-type "$principal_type" \
			--role "$role" \
			--scope "$scope" \
			--only-show-errors 1>/dev/null; then
			echo "[$role] role successfully assigned to the $principal_description on the $scope_description"
			return 0
		fi

		if [ "$attempt" -lt "$ROLE_ASSIGNMENT_RETRY_COUNT" ]; then
			echo "Attempt $attempt of $ROLE_ASSIGNMENT_RETRY_COUNT to assign the [$role] role failed; retrying in $ROLE_ASSIGNMENT_RETRY_SLEEP seconds..."
			sleep "$ROLE_ASSIGNMENT_RETRY_SLEEP"
		fi
	done

	echo "Failed to assign the [$role] role to the $principal_description on the $scope_description"
	exit 1
}

# Run a Key Vault operation until it succeeds. A role assigned on the key vault can take a few minutes to apply on
# Azure, and until then the vault, or Azure SQL on behalf of the server's identity, refuses the operation, so it is
# retried up to KEY_VAULT_RETRY_COUNT times, KEY_VAULT_RETRY_SLEEP seconds apart.
# $1: the description of the operation, used in messages
# $@: the command and its arguments
retry_key_vault_operation() {
	local description=$1
	local attempt
	shift

	for attempt in $(seq 1 "$KEY_VAULT_RETRY_COUNT"); do
		if "$@"; then
			return 0
		fi

		if [ "$attempt" -lt "$KEY_VAULT_RETRY_COUNT" ]; then
			echo "Attempt $attempt of $KEY_VAULT_RETRY_COUNT to $description failed (a role assignment on the key vault may still be propagating); retrying in $KEY_VAULT_RETRY_SLEEP seconds..."
			sleep "$KEY_VAULT_RETRY_SLEEP"
		fi
	done

	return 1
}

# Store a secret in the key vault, unless it already holds the same value. The value is never printed.
# $1: the secret name
# $2: the secret value
set_secret() {
	local secret_name=$1
	local secret_value=$2
	local current

	echo "Checking if the [$secret_name] secret actually exists in the [$KEY_VAULT_NAME] key vault..."
	current=$(az keyvault secret show \
		--vault-name "$KEY_VAULT_NAME" \
		--name "$secret_name" \
		--query value \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ -n $current && $current == "$secret_value" ]]; then
		echo "The [$secret_name] secret already holds the expected value in the [$KEY_VAULT_NAME] key vault"
		return 0
	fi

	echo "Setting the [$secret_name] secret in the [$KEY_VAULT_NAME] key vault..."
	if retry_key_vault_operation "set the [$secret_name] secret" az keyvault secret set \
		--vault-name "$KEY_VAULT_NAME" \
		--name "$secret_name" \
		--value "$secret_value" \
		--only-show-errors 1>/dev/null; then
		echo "The [$secret_name] secret was successfully set in the [$KEY_VAULT_NAME] key vault"
	else
		echo "Failed to set the [$secret_name] secret in the [$KEY_VAULT_NAME] key vault"
		exit 1
	fi
}

# Check if the resource group already exists
echo "Checking if [$RESOURCE_GROUP_NAME] resource group actually exists..."
az group show \
	--name "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$RESOURCE_GROUP_NAME] resource group actually exists"
	echo "Creating [$RESOURCE_GROUP_NAME] resource group..."

	az group create \
		--name "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$RESOURCE_GROUP_NAME] resource group successfully created"
	else
		echo "Failed to create [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$RESOURCE_GROUP_NAME] resource group already exists"
fi

# Check if the Log Analytics workspace already exists
echo "Checking if [$LOG_ANALYTICS_NAME] Log Analytics workspace already exists in the [$RESOURCE_GROUP_NAME] resource group..."
az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$LOG_ANALYTICS_NAME] Log Analytics workspace actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$LOG_ANALYTICS_NAME] Log Analytics workspace in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the Log Analytics workspace that receives the telemetry of Application Insights and the logs and metrics
	# of the diagnostic settings
	az monitor log-analytics workspace create \
		--name "$LOG_ANALYTICS_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--query-access "Enabled" \
		--retention-time 30 \
		--sku "PerNode" \
		--tags environment=test iac=az-cli \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$LOG_ANALYTICS_NAME] Log Analytics workspace successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$LOG_ANALYTICS_NAME] Log Analytics workspace in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$LOG_ANALYTICS_NAME] Log Analytics workspace already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Get the resource id of the Log Analytics workspace
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -z $LOG_ANALYTICS_ID ]]; then
	echo "Failed to retrieve the resource id of the [$LOG_ANALYTICS_NAME] Log Analytics workspace"
	exit 1
fi

# Check if the Application Insights component already exists
echo "Checking if [$APPLICATION_INSIGHTS_NAME] Application Insights component exists in the [$RESOURCE_GROUP_NAME] resource group..."
az monitor app-insights component show \
	--app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APPLICATION_INSIGHTS_NAME] Application Insights component exists in the [$RESOURCE_GROUP_NAME] resource group."
	echo "Creating [$APPLICATION_INSIGHTS_NAME] Application Insights component in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create a workspace-based Application Insights component that stores the telemetry of the web app in the Log
	# Analytics workspace
	az monitor app-insights component create \
		--app "$APPLICATION_INSIGHTS_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--application-type web \
		--workspace "$LOG_ANALYTICS_NAME" \
		--tags environment=test iac=az-cli \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$APPLICATION_INSIGHTS_NAME] Application Insights component created successfully in the [$RESOURCE_GROUP_NAME] resource group."
	else
		echo "Failed to create [$APPLICATION_INSIGHTS_NAME] Application Insights component in the [$RESOURCE_GROUP_NAME] resource group."
		exit 1
	fi
else
	echo "[$APPLICATION_INSIGHTS_NAME] Application Insights component already exists in the [$RESOURCE_GROUP_NAME] resource group."
fi

# Get the connection string of the Application Insights component
echo "Getting the connection string of the [$APPLICATION_INSIGHTS_NAME] Application Insights component..."
APPLICATION_INSIGHTS_CONNECTION_STRING=$(az monitor app-insights component show \
	--app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query connectionString \
	--output tsv \
	--only-show-errors)

if [[ -n $APPLICATION_INSIGHTS_CONNECTION_STRING ]]; then
	echo "Connection string of the [$APPLICATION_INSIGHTS_NAME] Application Insights component retrieved successfully."
else
	echo "Failed to retrieve the connection string of the [$APPLICATION_INSIGHTS_NAME] Application Insights component."
	exit 1
fi

# Check if the user-assigned managed identity of the SQL server already exists
echo "Checking if [$SQL_SERVER_IDENTITY_NAME] user-assigned managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az identity show \
	--name "$SQL_SERVER_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$SQL_SERVER_IDENTITY_NAME] user-assigned managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$SQL_SERVER_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the user-assigned managed identity the SQL server uses to reach the TDE protector key
	az identity create \
		--name "$SQL_SERVER_IDENTITY_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$SQL_SERVER_IDENTITY_NAME] user-assigned managed identity successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$SQL_SERVER_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$SQL_SERVER_IDENTITY_NAME] user-assigned managed identity already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

SQL_SERVER_IDENTITY_ID=$(az identity show \
	--name "$SQL_SERVER_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "id" \
	--output tsv)

SQL_SERVER_IDENTITY_PRINCIPAL_ID=$(az identity show \
	--name "$SQL_SERVER_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "principalId" \
	--output tsv)

if [[ -z "$SQL_SERVER_IDENTITY_ID" || -z "$SQL_SERVER_IDENTITY_PRINCIPAL_ID" ]]; then
	echo "Failed to retrieve the resource ID or principalId of [$SQL_SERVER_IDENTITY_NAME]"
	exit 1
fi

# Check if the user-assigned managed identity of the web app already exists
echo "Checking if [$WEB_APP_IDENTITY_NAME] user-assigned managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az identity show \
	--name "$WEB_APP_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$WEB_APP_IDENTITY_NAME] user-assigned managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$WEB_APP_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the user-assigned managed identity the web app reads the connection string and the certificate with
	az identity create \
		--name "$WEB_APP_IDENTITY_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$WEB_APP_IDENTITY_NAME] user-assigned managed identity successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$WEB_APP_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$WEB_APP_IDENTITY_NAME] user-assigned managed identity already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Retrieve the clientId, principalId and resource id of the user-assigned managed identity of the web app
echo "Retrieving the clientId, principalId and resource id of the [$WEB_APP_IDENTITY_NAME] managed identity..."
# tr drops the carriage return the Azure CLI ends each line with on Windows: mapfile keeps it, even with bash's igncr option
mapfile -t WEB_APP_IDENTITY_FIELDS < <(az identity show \
	--name "$WEB_APP_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[clientId, principalId, id]" \
	--output tsv \
	--only-show-errors | tr -d '\r')
WEB_APP_IDENTITY_CLIENT_ID="${WEB_APP_IDENTITY_FIELDS[0]:-}"
WEB_APP_IDENTITY_PRINCIPAL_ID="${WEB_APP_IDENTITY_FIELDS[1]:-}"
WEB_APP_IDENTITY_ID="${WEB_APP_IDENTITY_FIELDS[2]:-}"

if [[ -n $WEB_APP_IDENTITY_CLIENT_ID && -n $WEB_APP_IDENTITY_PRINCIPAL_ID && -n $WEB_APP_IDENTITY_ID ]]; then
	echo "[$WEB_APP_IDENTITY_NAME] managed identity: clientId [$WEB_APP_IDENTITY_CLIENT_ID], principalId [$WEB_APP_IDENTITY_PRINCIPAL_ID]"
else
	echo "Failed to retrieve the clientId, principalId and resource id of the [$WEB_APP_IDENTITY_NAME] managed identity"
	exit 1
fi

# Create a sql server
echo "Checking if [$SQL_SERVER_NAME] sql server exists in the [$RESOURCE_GROUP_NAME] resource group..."
az sql server show \
	--name $SQL_SERVER_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors &>/dev/null

if [ $? -eq 0 ]; then
	echo "[$SQL_SERVER_NAME] sql server already exists in the [$RESOURCE_GROUP_NAME] resource group."
else
	echo "[$SQL_SERVER_NAME] sql server does not exist in the [$RESOURCE_GROUP_NAME] resource group. Proceeding to create it."
	echo "Creating [$SQL_SERVER_NAME] sql server in the [$RESOURCE_GROUP_NAME] resource group..."
	az sql server create \
		--name $SQL_SERVER_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location $LOCATION \
		--admin-user $ADMIN_USER \
		--admin-password $ADMIN_PASSWORD \
		--assign-identity \
		--identity-type UserAssigned \
		--user-assigned-identity-id "$SQL_SERVER_IDENTITY_ID" \
		--primary-user-assigned-identity-id "$SQL_SERVER_IDENTITY_ID" \
		--minimal-tls-version 1.2 \
		--tags environment=test \
		--only-show-errors 1>/dev/null

	if [ $? == 0 ]; then
		echo "[$SQL_SERVER_NAME] sql server successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$SQL_SERVER_NAME] sql server in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
fi

# Check if the firewall rule already exists
echo "Checking if [$FIREWALL_RULE_NAME] firewall rule exists on the [$SQL_SERVER_NAME] sql server..."
az sql server firewall-rule show \
	--name "$FIREWALL_RULE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--server "$SQL_SERVER_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$FIREWALL_RULE_NAME] firewall rule exists on the [$SQL_SERVER_NAME] sql server"
	echo "Creating [$FIREWALL_RULE_NAME] firewall rule to allow all IP addresses..."

	# Add firewall rule to allow all local network addresses (for testing/development)
	az sql server firewall-rule create \
		--name "$FIREWALL_RULE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--server "$SQL_SERVER_NAME" \
		--start-ip-address 0.0.0.0 \
		--end-ip-address 255.255.255.255 \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$FIREWALL_RULE_NAME] firewall rule successfully created on the [$SQL_SERVER_NAME] sql server"
	else
		echo "Failed to create [$FIREWALL_RULE_NAME] firewall rule on the [$SQL_SERVER_NAME] sql server"
		exit 1
	fi
else
	echo "[$FIREWALL_RULE_NAME] firewall rule already exists on the [$SQL_SERVER_NAME] sql server"
fi

# Create database if it does not exist
echo "Checking if [$SQL_DATABASE_NAME] database exists in the [$SQL_SERVER_NAME] sql server..."
az sql db show \
	--name $SQL_DATABASE_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--server $SQL_SERVER_NAME \
	--only-show-errors &>/dev/null

if [ $? -eq 0 ]; then
	echo "[$SQL_DATABASE_NAME] database already exists in the [$SQL_SERVER_NAME] sql server."
else
	echo "Creating [$SQL_DATABASE_NAME] database with Provisioned compute model in the [$SQL_SERVER_NAME] sql server..."
	az sql db create \
		--name $SQL_DATABASE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--server $SQL_SERVER_NAME \
		--service-objective S0 \
		--compute-model Provisioned \
		--zone-redundant false \
		--tags environment=test \
		--only-show-errors 1>/dev/null

	if [ $? == 0 ]; then
		echo "[$SQL_DATABASE_NAME] database with Provisioned compute model successfully created in the [$SQL_SERVER_NAME] sql server"
	else
		echo "Failed to create [$SQL_DATABASE_NAME] with Provisioned compute model database in the [$SQL_SERVER_NAME] sql server"
		exit 1
	fi
fi

# Get the resource id of the database
SQL_DATABASE_ID=$(az sql db show \
	--name "$SQL_DATABASE_NAME" \
	--server "$SQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -z "$SQL_DATABASE_ID" ]]; then
	echo "Failed to retrieve the resource id of the [$SQL_DATABASE_NAME] database"
	exit 1
fi

# Check whether the diagnostic settings for the database already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SQL_DATABASE_NAME] database already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$SQL_DATABASE_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SQL_DATABASE_NAME] database actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SQL_DATABASE_NAME] database..."

	# Create the diagnostic settings for the database to send its resource logs and platform metrics to the Log
	# Analytics workspace. The database writes its logs to the AzureDiagnostics table: none of its categories has a
	# resource-specific table. The audit category (SQLSecurityAuditEvents) gets a diagnostic setting of its own below.
	# Its metrics come in three categories, all enabled: Basic, InstanceAndAppAdvanced, and WorkloadManagement, which
	# groups the metrics of dedicated SQL pools and so exports none for this database.
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$SQL_DATABASE_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "SQLInsights", "enabled": true},
			{"category": "AutomaticTuning", "enabled": true},
			{"category": "QueryStoreRuntimeStatistics", "enabled": true},
			{"category": "QueryStoreWaitStatistics", "enabled": true},
			{"category": "Errors", "enabled": true},
			{"category": "DatabaseWaitStatistics", "enabled": true},
			{"category": "Timeouts", "enabled": true},
			{"category": "Blocks", "enabled": true},
			{"category": "Deadlocks", "enabled": true}
		]' \
		--metrics '[
			{"category": "Basic", "enabled": true},
			{"category": "InstanceAndAppAdvanced", "enabled": true},
			{"category": "WorkloadManagement", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SQL_DATABASE_NAME] database successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SQL_DATABASE_NAME] database"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SQL_DATABASE_NAME] database already exist"
fi

# Turn on the auditing of the database with Azure Monitor as its target. The Azure CLI keeps the audit category
# (SQLSecurityAuditEvents) in a diagnostic setting of its own, named SQLSecurityAuditEvents_<id>, which it creates the
# first time and updates afterwards: the records of each batch run on the database and of each sign-in reach the
# workspace.
echo "Enabling the auditing of the [$SQL_DATABASE_NAME] database to the [$LOG_ANALYTICS_NAME] Log Analytics workspace..."
az sql db audit-policy update \
	--name "$SQL_DATABASE_NAME" \
	--server "$SQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--state Enabled \
	--log-analytics-target-state Enabled \
	--log-analytics-workspace-resource-id "$LOG_ANALYTICS_ID" \
	--only-show-errors 1>/dev/null

if [[ $? == 0 ]]; then
	echo "Auditing of the [$SQL_DATABASE_NAME] database to the [$LOG_ANALYTICS_NAME] Log Analytics workspace successfully enabled"
else
	echo "Failed to enable the auditing of the [$SQL_DATABASE_NAME] database"
	exit 1
fi

# Retrieve the fullyQualifiedDomainName of the SQL server
echo "Retrieving the fullyQualifiedDomainName of the [$SQL_SERVER_NAME] SQL server..."
SQL_SERVER_FQDN=$(az sql server show \
	--name "$SQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "fullyQualifiedDomainName" \
	--output tsv)

if [ -z "$SQL_SERVER_FQDN" ]; then
	echo "Failed to retrieve the fullyQualifiedDomainName of the SQL server"
	exit 1
fi

#if [[ $ENVIRONMENT == "LocalStack" ]]; then
#	MSSQL_HOST_PORT=$(docker ps --filter "ancestor=mcr.microsoft.com/mssql/server:2022-latest" --format "{{.Ports}}" | grep -oP '0\.0\.0\.0:\K[0-9]+(?=->1433)' | head -1)
#	if [ -n "$MSSQL_HOST_PORT" ]; then
#		SQL_SERVER_FQDN_WITH_PORT="127.0.0.1,$MSSQL_HOST_PORT"
#		echo "Using local SQL Server at [$SQL_SERVER_FQDN_WITH_PORT]"
#	fi
#fi

echo "Checking if login [$DATABASE_USER_NAME] exists at server level..."
if [[ $(sqlcmd -S "$SQL_SERVER_FQDN" -d master -U "$ADMIN_USER" -P "$ADMIN_PASSWORD" -N -C -h -1 -W \
	-Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.sql_logins WHERE name = '$DATABASE_USER_NAME';" | tr -d '[:space:]') == 1 ]]; then
	echo "Login [$DATABASE_USER_NAME] already exists at server level"
else
	# Create server-level login
	echo "Creating login [$DATABASE_USER_NAME] at server level..."
	sqlcmd -S "$SQL_SERVER_FQDN" \
	    -d master \
	    -U "$ADMIN_USER" \
	    -P "$ADMIN_PASSWORD" \
	    -N -C \
	    -Q "IF NOT EXISTS (SELECT * FROM sys.sql_logins WHERE name = '$DATABASE_USER_NAME')
	            CREATE LOGIN [$DATABASE_USER_NAME] WITH PASSWORD = '$DATABASE_USER_PASSWORD';" \
	    -V 1

	if [ $? -eq 0 ]; then
		echo "Login [$DATABASE_USER_NAME] created successfully"
	else
		echo "Failed to create login [$DATABASE_USER_NAME]"
		exit 1
	fi
fi

echo "Checking if user [$DATABASE_USER_NAME] exists in database [$SQL_DATABASE_NAME]..."
if [[ $(sqlcmd -S "$SQL_SERVER_FQDN" -d "$SQL_DATABASE_NAME" -U "$ADMIN_USER" -P "$ADMIN_PASSWORD" -N -C -h -1 -W \
	-Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.database_principals WHERE name = '$DATABASE_USER_NAME';" | tr -d '[:space:]') == 1 ]]; then
	echo "User [$DATABASE_USER_NAME] already exists in database [$SQL_DATABASE_NAME]"
else
	# Create database user
	echo "Creating user [$DATABASE_USER_NAME] in database [$SQL_DATABASE_NAME]..."
	sqlcmd -S "$SQL_SERVER_FQDN" \
	    -d "$SQL_DATABASE_NAME" \
	    -U "$ADMIN_USER" \
	    -P "$ADMIN_PASSWORD" \
	    -N -C \
	    -Q "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$DATABASE_USER_NAME')
	          CREATE USER [$DATABASE_USER_NAME] FOR LOGIN [$DATABASE_USER_NAME];" \
	    -V 1

	if [ $? -eq 0 ]; then
		echo "User [$DATABASE_USER_NAME] created successfully in database [$SQL_DATABASE_NAME]"
	else
		echo "Failed to create user [$DATABASE_USER_NAME]"
		exit 1
	fi
fi

# Grant permissions including DDL rights
echo "Granting permissions to [$DATABASE_USER_NAME]..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d "$SQL_DATABASE_NAME" \
	-U "$ADMIN_USER" \
	-P "$ADMIN_PASSWORD" \
  -N -C \
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
  -N -C \
	-Q "SELECT SYSTEM_USER AS CurrentUser, DB_NAME() AS CurrentDatabase, GETDATE() AS CurrentTime;" \
	-V 1

if [ $? -eq 0 ]; then
	echo "Connection test successful with user [$DATABASE_USER_NAME]"
else
	echo "Connection test failed with user [$DATABASE_USER_NAME]"
	exit 1
fi

echo "Checking if the [Activities] table exists..."
if [[ $(sqlcmd -S "$SQL_SERVER_FQDN" -d "$SQL_DATABASE_NAME" -U "$DATABASE_USER_NAME" -P "$DATABASE_USER_PASSWORD" -N -C -h -1 -W \
	-Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables WHERE name = 'Activities' AND schema_id = SCHEMA_ID('dbo');" | tr -d '[:space:]') == 1 ]]; then
	echo "[Activities] table already exists"
else
	# Create table
	echo "Creating test [Activities] table..."
	sqlcmd -S "$SQL_SERVER_FQDN" \
		-d "$SQL_DATABASE_NAME" \
		-U "$DATABASE_USER_NAME" \
		-P "$DATABASE_USER_PASSWORD" \
	  -N -C \
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
fi

# Insert the test data, only the rows the table does not hold yet, so that a second run adds no duplicates
echo "Inserting the missing test data into [Activities] table..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d "$SQL_DATABASE_NAME" \
	-U "$DATABASE_USER_NAME" \
	-P "$DATABASE_USER_PASSWORD" \
  -N -C \
	-Q "INSERT INTO Activities (username, activity, timestamp)
			SELECT seed.username, seed.activity, GETDATE()
			FROM (VALUES
				('paolo', 'Go to Paris'),
				('paolo', 'Go to London'),
				('paolo', 'Go to Mexico')) AS seed (username, activity)
			WHERE NOT EXISTS (
				SELECT 1 FROM Activities existing
				WHERE existing.username = seed.username AND existing.activity = seed.activity);" \
	-V 1

if [ $? -eq 0 ]; then
	echo "Missing test data inserted successfully into [Activities] table"
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
  -N -C \
	-Q "SELECT * FROM Activities;" \
	-V 1

if [ $? -eq 0 ]; then
	echo "Test data queried successfully from [Activities] table"
else
	echo "Failed to query test data from [Activities] table"
	exit 1
fi

# Check if the App Service plan already exists
echo "Checking if [$APP_SERVICE_PLAN_NAME] App Service plan actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az appservice plan show \
	--name "$APP_SERVICE_PLAN_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APP_SERVICE_PLAN_NAME] App Service plan actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$APP_SERVICE_PLAN_NAME] App Service plan in the [$RESOURCE_GROUP_NAME] resource group..."

	az appservice plan create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$APP_SERVICE_PLAN_NAME" \
		--location "$LOCATION" \
		--sku "$APP_SERVICE_PLAN_SKU" \
		--is-linux \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$APP_SERVICE_PLAN_NAME] App Service plan successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$APP_SERVICE_PLAN_NAME] App Service plan in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$APP_SERVICE_PLAN_NAME] App Service plan already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the web app already exists
echo "Checking if web app [$WEB_APP_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group..."
az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No web app [$WEB_APP_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating web app [$WEB_APP_NAME] with the [$WEB_APP_IDENTITY_NAME] user-assigned managed identity..."

	# Create the web app with the user-assigned managed identity it reads the key vault with
	az webapp create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--plan "$APP_SERVICE_PLAN_NAME" \
		--name "$WEB_APP_NAME" \
		--runtime "$RUNTIME:$RUNTIME_VERSION" \
		--assign-identity "$WEB_APP_IDENTITY_ID" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Web app [$WEB_APP_NAME] created successfully."
	else
		echo "Failed to create web app [$WEB_APP_NAME]."
		exit 1
	fi
else
	echo "Web app [$WEB_APP_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Making sure the [$WEB_APP_IDENTITY_NAME] user-assigned managed identity is assigned to the [$WEB_APP_NAME] web app..."

	# Idempotent: assigning an identity that is already assigned is a no-op
	az webapp identity assign \
		--name "$WEB_APP_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--identities "$WEB_APP_IDENTITY_ID" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "[$WEB_APP_IDENTITY_NAME] user-assigned managed identity is assigned to the [$WEB_APP_NAME] web app"
	else
		echo "Failed to assign the [$WEB_APP_IDENTITY_NAME] user-assigned managed identity to the [$WEB_APP_NAME] web app"
		exit 1
	fi
fi

# Recover the key vault if a previous run left it soft-deleted.
# Deleting a key vault only soft-deletes it, and the name stays reserved for the retention period, so
# re-running this script after deleting the resource group fails the create below with
# "A vault with the same name already exists in deleted state". The vault has purge protection, which
# Azure SQL requires on the vault of a TDE protector key, so it cannot be purged either: recovering
# restores it with its contents, which is what a re-run wants.
# The vault's own location, not $LOCATION: a soft-deleted vault stays in the region it was deleted in,
# so recovering it with a different region fails.
DELETED_KEY_VAULT_LOCATION=$(az keyvault list-deleted \
	--query "[?name=='$KEY_VAULT_NAME'].properties.location | [0]" \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $DELETED_KEY_VAULT_LOCATION ]]; then
	echo "[$KEY_VAULT_NAME] key vault exists in a soft-deleted state in [$DELETED_KEY_VAULT_LOCATION]"
	echo "Recovering the [$KEY_VAULT_NAME] key vault..."

	az keyvault recover \
		--name "$KEY_VAULT_NAME" \
		--location "$DELETED_KEY_VAULT_LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$KEY_VAULT_NAME] key vault successfully recovered"
	else
		echo "Failed to recover the soft-deleted [$KEY_VAULT_NAME] key vault"
		echo "Its purge protection keeps the name reserved until the retention period ends: change PREFIX or SUFFIX and re-run this script"
		exit 1
	fi
fi

# Check if the key vault already exists
echo "Checking if [$KEY_VAULT_NAME] key vault actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az keyvault show \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$KEY_VAULT_NAME] key vault actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$KEY_VAULT_NAME] key vault in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the key vault with the Azure RBAC permission model, which the role assignments below need, and with
	# purge protection, which Azure SQL requires on the vault of a TDE protector key
	az keyvault create \
		--name "$KEY_VAULT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--enable-rbac-authorization true \
		--enable-purge-protection true \
		--retention-days 7 \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$KEY_VAULT_NAME] key vault successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$KEY_VAULT_NAME] key vault in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$KEY_VAULT_NAME] key vault already exists in the [$RESOURCE_GROUP_NAME] resource group"

	# A vault created by an earlier version of this sample uses access policies: switch it to the Azure RBAC
	# permission model, which the role assignments below need
	if [[ $(az keyvault show \
		--name "$KEY_VAULT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query "properties.enableRbacAuthorization" \
		--output tsv \
		--only-show-errors) != "true" ]]; then
		echo "Switching the [$KEY_VAULT_NAME] key vault to the Azure RBAC permission model..."

		az keyvault update \
			--name "$KEY_VAULT_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--enable-rbac-authorization true \
			--only-show-errors 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "The [$KEY_VAULT_NAME] key vault now uses the Azure RBAC permission model"
		else
			echo "Failed to switch the [$KEY_VAULT_NAME] key vault to the Azure RBAC permission model"
			exit 1
		fi
	fi
fi

# Retrieve the vault URI and the resource id of the key vault. The URI is read back from the service:
# https://<vault>.vault.azure.net/ on Azure, https://<vault>.vault.azure.localhost.localstack.cloud:4566/ on
# the emulator.
echo "Retrieving the vault URI and the resource id of the [$KEY_VAULT_NAME] key vault..."
# tr drops the carriage return the Azure CLI ends each line with on Windows: mapfile keeps it, even with bash's igncr option
mapfile -t KEY_VAULT_FIELDS < <(az keyvault show \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[properties.vaultUri, id]" \
	--output tsv \
	--only-show-errors | tr -d '\r')
KEY_VAULT_URI="${KEY_VAULT_FIELDS[0]:-}"
KEY_VAULT_ID="${KEY_VAULT_FIELDS[1]:-}"

if [[ -n $KEY_VAULT_URI && -n $KEY_VAULT_ID ]]; then
	echo "[$KEY_VAULT_NAME] key vault URI: $KEY_VAULT_URI"
else
	echo "Failed to retrieve the vault URI and the resource id of the [$KEY_VAULT_NAME] key vault"
	exit 1
fi

# Check whether the diagnostic settings for the key vault already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$KEY_VAULT_NAME] key vault already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$KEY_VAULT_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$KEY_VAULT_NAME] key vault actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$KEY_VAULT_NAME] key vault..."

	# Create the diagnostic settings for the key vault to send logs to the Log Analytics workspace, in the
	# resource-specific AZKVAuditLogs and AZKVPolicyEvaluationDetailsLogs tables rather than AzureDiagnostics
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$KEY_VAULT_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--export-to-resource-specific true \
		--logs '[
			{"category": "AuditEvent", "enabled": true},
			{"category": "AzurePolicyEvaluationDetails", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$KEY_VAULT_NAME] key vault successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$KEY_VAULT_NAME] key vault"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$KEY_VAULT_NAME] key vault already exist"
fi

# Resolve the object id of the deploying principal. The vault uses the RBAC permission model, so writing the
# secret, the certificate and the key below needs the Key Vault Secrets Officer, Certificates Officer and Crypto
# Officer roles on the vault; the script grants them to whoever runs it, a user or a service principal. The lookup
# goes through Microsoft Graph; when it fails the script continues and the roles become a prerequisite (see the
# README).
ACCOUNT_USER_TYPE=$(az account show --query user.type --output tsv --only-show-errors)
ACCOUNT_USER_NAME=$(az account show --query user.name --output tsv --only-show-errors)

if [[ $ACCOUNT_USER_TYPE == "user" ]]; then
	DEPLOYER_PRINCIPAL_TYPE="User"
	DEPLOYER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv --only-show-errors 2>/dev/null)
else
	DEPLOYER_PRINCIPAL_TYPE="ServicePrincipal"
	DEPLOYER_OBJECT_ID=$(az ad sp show --id "$ACCOUNT_USER_NAME" --query id --output tsv --only-show-errors 2>/dev/null)
fi

# Microsoft Graph lookups need directory permissions a pipeline principal often lacks. Fall back to the oid claim of
# the CLI's own access token, which identifies the same principal without any Graph call.
if [[ -z $DEPLOYER_OBJECT_ID ]]; then
	DEPLOYER_OBJECT_ID=$(az account get-access-token --query accessToken --output tsv --only-show-errors 2>/dev/null |
		cut -d. -f2 | tr '_-' '/+' | awk '{ pad = length($0) % 4; if (pad == 2) $0 = $0 "=="; else if (pad == 3) $0 = $0 "="; print }' |
		base64 -d 2>/dev/null | jq -r '.oid // empty' 2>/dev/null)
fi

if [[ -n $DEPLOYER_OBJECT_ID ]]; then
	echo "Deploying principal [$ACCOUNT_USER_NAME] ($DEPLOYER_PRINCIPAL_TYPE) has object id [$DEPLOYER_OBJECT_ID]"
	for ROLE in "$KEY_VAULT_SECRETS_OFFICER_ROLE" "$KEY_VAULT_CERTIFICATES_OFFICER_ROLE" "$KEY_VAULT_CRYPTO_OFFICER_ROLE"; do
		ensure_role_assignment "$DEPLOYER_OBJECT_ID" "$DEPLOYER_PRINCIPAL_TYPE" "$ROLE" "$KEY_VAULT_ID" "deploying principal [$ACCOUNT_USER_NAME]" "[$KEY_VAULT_NAME] key vault"
	done
else
	echo "WARNING: could not resolve the object id of the deploying principal [$ACCOUNT_USER_NAME]; the [$KEY_VAULT_SECRETS_OFFICER_ROLE], [$KEY_VAULT_CERTIFICATES_OFFICER_ROLE] and [$KEY_VAULT_CRYPTO_OFFICER_ROLE] roles on the [$KEY_VAULT_NAME] key vault must already be assigned to it"
fi

# The web app reads the connection string and the private key of its certificate as secrets (Key Vault Secrets
# User), and the certificate itself (Key Vault Certificate User), with its user-assigned managed identity. The SQL
# server wraps and unwraps its database encryption keys with the TDE protector key through its own user-assigned
# managed identity (Key Vault Crypto Service Encryption User).
ensure_role_assignment "$WEB_APP_IDENTITY_PRINCIPAL_ID" "ServicePrincipal" "$KEY_VAULT_SECRETS_USER_ROLE" "$KEY_VAULT_ID" "[$WEB_APP_IDENTITY_NAME] managed identity" "[$KEY_VAULT_NAME] key vault"
ensure_role_assignment "$WEB_APP_IDENTITY_PRINCIPAL_ID" "ServicePrincipal" "$KEY_VAULT_CERTIFICATE_USER_ROLE" "$KEY_VAULT_ID" "[$WEB_APP_IDENTITY_NAME] managed identity" "[$KEY_VAULT_NAME] key vault"
ensure_role_assignment "$SQL_SERVER_IDENTITY_PRINCIPAL_ID" "ServicePrincipal" "$KEY_VAULT_CRYPTO_SERVICE_ENCRYPTION_USER_ROLE" "$KEY_VAULT_ID" "[$SQL_SERVER_IDENTITY_NAME] managed identity" "[$KEY_VAULT_NAME] key vault"

# Build connection string
SQL_CONNECTION_STRING="Server=tcp:${SQL_SERVER_FQDN},1433;Database=${SQL_DATABASE_NAME};User ID=${DATABASE_USER_NAME};Password=${DATABASE_USER_PASSWORD};Encrypt=yes;TrustServerCertificate=yes;Connection Timeout=30;"

# Store the connection string as a secret, unless the vault already holds it
set_secret "$SECRET_NAME" "$SQL_CONNECTION_STRING"

# Create the certificate the web app serves HTTPS with on port 8443, unless the vault already holds it
echo "Checking if the [$CERT_NAME] certificate actually exists in the [$KEY_VAULT_NAME] key vault..."
if az keyvault certificate show \
	--vault-name "$KEY_VAULT_NAME" \
	--name "$CERT_NAME" \
	--only-show-errors &>/dev/null; then
	echo "The [$CERT_NAME] certificate already exists in the [$KEY_VAULT_NAME] key vault"
else
	echo "Creating the [$CERT_NAME] certificate in the [$KEY_VAULT_NAME] key vault..."
	if retry_key_vault_operation "create the [$CERT_NAME] certificate" az keyvault certificate create \
		--vault-name "$KEY_VAULT_NAME" \
		--name "$CERT_NAME" \
		--policy '{
			"issuerParameters": {"name": "Self"},
			"keyProperties": {"exportable": true, "keySize": 2048, "keyType": "RSA", "reuseKey": false},
			"secretProperties": {"contentType": "application/x-pkcs12"},
			"x509CertificateProperties": {"subject": "CN=sample-web-app-sql", "validityInMonths": 12}
		}' \
		--only-show-errors 1>/dev/null; then
		echo "The [$CERT_NAME] certificate was successfully created in the [$KEY_VAULT_NAME] key vault"
	else
		echo "Failed to create the [$CERT_NAME] certificate in the [$KEY_VAULT_NAME] key vault"
		exit 1
	fi
fi

# Create the RSA key that protects the database encryption keys of the SQL server, unless the vault already holds it:
# a new key would add a version, and with it a new server key and a new TDE protector, on every run
echo "Checking if the [$TDE_KEY_NAME] key actually exists in the [$KEY_VAULT_NAME] key vault..."
TDE_KEY_ID=$(az keyvault key show \
	--vault-name "$KEY_VAULT_NAME" \
	--name "$TDE_KEY_NAME" \
	--query "key.kid" \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $TDE_KEY_ID ]]; then
	echo "The [$TDE_KEY_NAME] key already exists in the [$KEY_VAULT_NAME] key vault: [$TDE_KEY_ID]"
else
	echo "Creating the [$TDE_KEY_NAME] key in the [$KEY_VAULT_NAME] key vault..."
	if ! retry_key_vault_operation "create the [$TDE_KEY_NAME] key" az keyvault key create \
		--vault-name "$KEY_VAULT_NAME" \
		--name "$TDE_KEY_NAME" \
		--kty RSA \
		--size 2048 \
		--ops wrapKey unwrapKey \
		--only-show-errors 1>/dev/null; then
		echo "Failed to create the [$TDE_KEY_NAME] key in the [$KEY_VAULT_NAME] key vault"
		exit 1
	fi

	TDE_KEY_ID=$(az keyvault key show \
		--vault-name "$KEY_VAULT_NAME" \
		--name "$TDE_KEY_NAME" \
		--query "key.kid" \
		--output tsv \
		--only-show-errors)

	if [[ -n $TDE_KEY_ID ]]; then
		echo "The [$TDE_KEY_NAME] key was successfully created in the [$KEY_VAULT_NAME] key vault: [$TDE_KEY_ID]"
	else
		echo "Failed to retrieve the id of the [$TDE_KEY_NAME] key in the [$KEY_VAULT_NAME] key vault"
		exit 1
	fi
fi

# Register the key on the SQL server and make it the TDE protector. The generic az resource create
# is used because az sql server key create and az sql server tde-key set only accept key ids on the
# public Key Vault domains, which rejects the key ids the LocalStack emulator issues.
SQL_SERVER_ID=$(az sql server show \
	--name "$SQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "id" \
	--output tsv)
SERVER_KEY_NAME="${KEY_VAULT_NAME}_${TDE_KEY_NAME}_${TDE_KEY_ID##*/}"

# Check if the key is already registered on the SQL server
echo "Checking if key [$TDE_KEY_NAME] is registered on the [$SQL_SERVER_NAME] sql server..."
az resource show \
	--id "$SQL_SERVER_ID/keys/$SERVER_KEY_NAME" \
	--api-version 2023-08-01 \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	# Azure SQL checks that the server's identity can get, wrap and unwrap the key before it adds it, so the call is
	# retried until the Key Vault Crypto Service Encryption User assignment above applies
	echo "Adding key [$TDE_KEY_NAME] to the [$SQL_SERVER_NAME] sql server..."
	if retry_key_vault_operation "add the [$TDE_KEY_NAME] key to the [$SQL_SERVER_NAME] sql server" az resource create \
		--id "$SQL_SERVER_ID/keys/$SERVER_KEY_NAME" \
		--api-version 2023-08-01 \
		--properties "{\"serverKeyType\": \"AzureKeyVault\", \"uri\": \"$TDE_KEY_ID\"}" \
		--only-show-errors 1>/dev/null; then
		echo "Key [$TDE_KEY_NAME] added successfully to the [$SQL_SERVER_NAME] sql server."
	else
		echo "Failed to add key [$TDE_KEY_NAME] to the [$SQL_SERVER_NAME] sql server."
		exit 1
	fi
else
	echo "Key [$TDE_KEY_NAME] is already registered on the [$SQL_SERVER_NAME] sql server."
fi

# Check if the key is already the auto-rotated TDE protector of the SQL server: the server always has a protector, so
# the script sets it only when it is a different key
echo "Checking the TDE protector of the [$SQL_SERVER_NAME] sql server..."
CURRENT_PROTECTOR=$(az resource show \
	--id "$SQL_SERVER_ID/encryptionProtector/current" \
	--api-version 2023-08-01 \
	--query "join('/', [properties.serverKeyName, to_string(properties.autoRotationEnabled)])" \
	--output tsv \
	--only-show-errors 2>/dev/null | tr -d '\r')

if [[ $CURRENT_PROTECTOR != "$SERVER_KEY_NAME/true" ]]; then
	echo "Setting key [$TDE_KEY_NAME] as the TDE protector of the [$SQL_SERVER_NAME] sql server..."
	az resource create \
		--id "$SQL_SERVER_ID/encryptionProtector/current" \
		--api-version 2023-08-01 \
		--properties "{\"serverKeyType\": \"AzureKeyVault\", \"serverKeyName\": \"$SERVER_KEY_NAME\", \"autoRotationEnabled\": true}" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Key [$TDE_KEY_NAME] set successfully as the TDE protector of the [$SQL_SERVER_NAME] sql server."
	else
		echo "Failed to set key [$TDE_KEY_NAME] as the TDE protector of the [$SQL_SERVER_NAME] sql server."
		exit 1
	fi
else
	echo "Key [$TDE_KEY_NAME] is already the auto-rotated TDE protector of the [$SQL_SERVER_NAME] sql server."
fi

# Set web app settings
# Pass Key Vault name and secret name as app settings.
# The .NET SDK will retrieve the actual connection string value from Key Vault, authenticating with the
# user-assigned managed identity that AZURE_CLIENT_ID selects.
echo "Setting web app settings for [$WEB_APP_NAME]..."
az webapp config appsettings set \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--settings \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	KEY_VAULT_NAME="$KEY_VAULT_NAME" \
	SECRET_NAME="$SECRET_NAME" \
	LOGIN_NAME="$LOGIN_NAME" \
	KEYVAULT_URI="$KEY_VAULT_URI" \
	CERT_NAME="$CERT_NAME" \
	AZURE_CLIENT_ID="$WEB_APP_IDENTITY_CLIENT_ID" \
	APPLICATIONINSIGHTS_CONNECTION_STRING="$APPLICATION_INSIGHTS_CONNECTION_STRING" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app settings for [$WEB_APP_NAME] set successfully."
else
	echo "Failed to set web app settings for [$WEB_APP_NAME]."
	exit 1
fi

# Get the resource ids of the web app and of its App Service plan
WEB_APP_ID=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
APP_SERVICE_PLAN_ID=$(az appservice plan show \
	--name "$APP_SERVICE_PLAN_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -z $WEB_APP_ID || -z $APP_SERVICE_PLAN_ID ]]; then
	echo "Failed to retrieve the resource ids of the [$WEB_APP_NAME] web app and of its App Service plan"
	exit 1
fi

# Check whether the diagnostic settings for the web app already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$WEB_APP_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app..."

	# Create the diagnostic settings for the web app to send its logs and metrics to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$WEB_APP_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "AppServiceHTTPLogs", "enabled": true},
			{"category": "AppServiceConsoleLogs", "enabled": true},
			{"category": "AppServiceAppLogs", "enabled": true},
			{"category": "AppServiceAuditLogs", "enabled": true},
			{"category": "AppServiceIPSecAuditLogs", "enabled": true},
			{"category": "AppServicePlatformLogs", "enabled": true},
			{"category": "AppServiceAuthenticationLogs", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app already exist"
fi

# Check whether the diagnostic settings for the App Service plan already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$APP_SERVICE_PLAN_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan..."

	# Create the diagnostic settings for the App Service plan to send its metrics to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$APP_SERVICE_PLAN_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan already exist"
fi

# Check whether the diagnostic settings for the Log Analytics workspace already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$LOG_ANALYTICS_NAME] Log Analytics workspace already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$LOG_ANALYTICS_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$LOG_ANALYTICS_NAME] Log Analytics workspace actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$LOG_ANALYTICS_NAME] Log Analytics workspace..."

	# Create the diagnostic settings that send the audit records of the queries run on the workspace (LAQueryLogs) and its platform metrics to the workspace itself
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$LOG_ANALYTICS_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "Audit", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$LOG_ANALYTICS_NAME] Log Analytics workspace successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$LOG_ANALYTICS_NAME] Log Analytics workspace"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$LOG_ANALYTICS_NAME] Log Analytics workspace already exist"
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
zip -r "$ZIPFILE" . -x "bin/*" "obj/*" "publish/*" "*.zip"

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
az webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app [$WEB_APP_NAME] deployed successfully."
else
	echo "Failed to deploy web app [$WEB_APP_NAME]."
	exit 1
fi

# Get web app URL
WEB_APP_URL=$(az webapp show \
    --name "$WEB_APP_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query "defaultHostName" \
    --output tsv)

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi
