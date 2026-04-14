#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
SQL_SERVER_NAME="${PREFIX}-sqlserver-${SUFFIX}"
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
RUNTIME="python"
RUNTIME_VERSION="3.13"
DEPLOY_APP=1
KEY_VAULT_NAME="${PREFIX}-kv-${SUFFIX}"
SECRET_NAME="${PREFIX}-secret-${SUFFIX}"
CERT_NAME="${PREFIX}-cert-${SUFFIX}"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit
# Create a resource group
echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
az group create \
	--name $RESOURCE_GROUP_NAME \
	--location $LOCATION \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Resource group [$RESOURCE_GROUP_NAME] created successfully."
else
	echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
	exit 1
fi

# Create a sql server
echo "Checking if [$SQL_SERVER_NAME] sql server exists in the [$RESOURCE_GROUP_NAME] resource group..."
az sql server show \
	--name $SQL_SERVER_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors &>/dev/null

if [ $? -eq 0 ]; then
	echo "[$SQL_SERVER_NAME] sql server already exists in the [$RESOURCE_GROUP_NAME] resource group. Exiting script."
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
		--identity-type SystemAssigned \
		--minimal-tls-version 1.2 \
		--tags environment=test \
		--only-show-errors 1>/dev/null

	if [ $? == 0 ]; then
		echo "[$SQL_SERVER_NAME] sql server successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$SQL_SERVER_NAME] sql server in the [$RESOURCE_GROUP_NAME] resource group"
		exit
	fi
fi

# Add firewall rule to allow all local network addresses (for testing/development)
echo "Creating firewall rule to allow all IP addresses..."
az sql server firewall-rule create \
	--name $FIREWALL_RULE_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--server $SQL_SERVER_NAME \
	--start-ip-address 0.0.0.0 \
	--end-ip-address 255.255.255.255 \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Firewall rule [AllowLocalNetwork] created successfully"
else
	echo "Failed to create firewall rule"
	exit 1
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

# Create table
echo "Creating test [Products] table..."
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

# Insert data
echo "Inserting test data into [Activities] table..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d "$SQL_DATABASE_NAME" \
	-U "$DATABASE_USER_NAME" \
	-P "$DATABASE_USER_PASSWORD" \
  -N -C \
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
  -N -C \
	-Q "SELECT * FROM Activities;" \
	-V 1

if [ $? -eq 0 ]; then
	echo "Test data queried successfully from [Activities] table"
else
	echo "Failed to query test data from [Activities] table"
	exit 1
fi

# Create App Service Plan
echo "Creating App Service Plan [$APP_SERVICE_PLAN_NAME]..."
az appservice plan create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_SERVICE_PLAN_NAME" \
	--location "$LOCATION" \
	--sku "$APP_SERVICE_PLAN_SKU" \
	--is-linux \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "App Service Plan [$APP_SERVICE_PLAN_NAME] created successfully."
else
	echo "Failed to create App Service Plan [$APP_SERVICE_PLAN_NAME]."
	exit 1
fi

# Create the web app
echo "Creating web app [$WEB_APP_NAME]..."
az webapp create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--plan "$APP_SERVICE_PLAN_NAME" \
	--name "$WEB_APP_NAME" \
	--runtime "$RUNTIME:$RUNTIME_VERSION" \
	--assign-identity \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app [$WEB_APP_NAME] created successfully."
else
	echo "Failed to create web app [$WEB_APP_NAME]."
	exit 1
fi

# Get Web App principal ID
PRINCIPAL_ID=$(az webapp identity show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "principalId" \
	--output tsv)

if [ -z "$PRINCIPAL_ID" ]; then
	echo "Failed to retrieve principalId for web app [$WEB_APP_NAME]"
	exit 1
fi

# Create Key Vault
echo "Creating Key Vault [$KEY_VAULT_NAME]..."
az keyvault create \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--enable-rbac-authorization false \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Key Vault [$KEY_VAULT_NAME] created successfully."
else
	echo "Failed to create Key Vault [$KEY_VAULT_NAME]."
	exit 1
fi

# Assign access policy to Web App managed identity
echo "Assigning Key Vault access policy to Web App..."
az keyvault set-policy \
	--name "$KEY_VAULT_NAME" \
	--object-id "$PRINCIPAL_ID" \
	--secret-permissions get \
	--certificate-permissions get \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Key Vault access policy assigned successfully."
else
	echo "Failed to assign Key Vault access policy."
	exit 1
fi

# Build connection string
SQL_CONNECTION_STRING="Server=tcp:${SQL_SERVER_FQDN},1433;Database=${SQL_DATABASE_NAME};User ID=${DATABASE_USER_NAME};Password=${DATABASE_USER_PASSWORD};Encrypt=yes;TrustServerCertificate=yes;Connection Timeout=30;"

# Create secret
echo "Creating secret [$SECRET_NAME] in Key Vault..."
az keyvault secret set \
	--vault-name "$KEY_VAULT_NAME" \
	--name "$SECRET_NAME" \
	--value "$SQL_CONNECTION_STRING" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Secret [$SECRET_NAME] created successfully."
else
	echo "Failed to create secret [$SECRET_NAME]."
	exit 1
fi

# Create certificate in Key Vault
echo "Creating certificate [$CERT_NAME] in Key Vault [$KEY_VAULT_NAME]..."
az keyvault certificate create \
    --vault-name "$KEY_VAULT_NAME" \
    --name "$CERT_NAME" \
    --policy '{
        "issuerParameters": {"name": "Self"},
        "keyProperties": {"exportable": true, "keySize": 2048, "keyType": "RSA", "reuseKey": false},
        "secretProperties": {"contentType": "application/x-pkcs12"},
        "x509CertificateProperties": {"subject": "CN=sample-web-app-sql", "validityInMonths": 12}
    }' \
    --only-show-errors

if [ $? -eq 0 ]; then
	echo "Certificate [$CERT_NAME] created successfully in Key Vault [$KEY_VAULT_NAME]."
else
	echo "Failed to create certificate [$CERT_NAME] in Key Vault [$KEY_VAULT_NAME]."
	exit 1
fi

# Get Key Vault URI
echo "Retrieving Key Vault URI..."
KEYVAULT_URI=$(az keyvault show \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "properties.vaultUri" \
	--output tsv)

if [ -z "$KEYVAULT_URI" ]; then
	echo "Failed to retrieve Key Vault URI."
	exit 1
fi
echo "Key Vault URI: [$KEYVAULT_URI]"

# Set web app settings
# Pass Key Vault name and secret name as app settings.
# The Python SDK will retrieve the actual connection string value from Key Vault.
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
	KEYVAULT_URI="$KEYVAULT_URI" \
	CERT_NAME="$CERT_NAME" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app settings for [$WEB_APP_NAME] set successfully."
else
	echo "Failed to set web app settings for [$WEB_APP_NAME]."
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
zip -r "$ZIPFILE" app.py activities.py database.py certificates.py static templates requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
az webapp deploy \
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
