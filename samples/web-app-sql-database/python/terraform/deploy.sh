#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
ADMIN_USER='sqladmin'
ADMIN_PASSWORD='P@ssw0rd1234!'
DATABASE_USER_NAME='testuser'
DATABASE_USER_PASSWORD='TestP@ssw0rd123'
SECRET_NAME="${PREFIX}-secret-${SUFFIX}"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"
DEPLOY_APP=1
RBAC_PROPAGATION_DELAY="${RBAC_PROPAGATION_DELAY:-60s}"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Dual-target provider configuration. providers.tf hardcodes nothing: the azurerm provider reads its endpoints and the
# target subscription from the ARM_* environment variables exported here.
# - On both targets: the subscription and tenant of the active az account.
# - Only when the active az cloud is LocalStack: the emulator's metadata endpoint, taken from the az cloud registration
#   that `lstk az start-interception` created, so nothing is hardcoded here either.
ACTIVE_CLOUD=$(az cloud show --query name --output tsv --only-show-errors)
ARM_SUBSCRIPTION_ID=$(az account show --query id --output tsv --only-show-errors)
ARM_TENANT_ID=$(az account show --query tenantId --output tsv --only-show-errors)
export ARM_SUBSCRIPTION_ID ARM_TENANT_ID

if [[ $ACTIVE_CLOUD == "LocalStack" ]]; then
	RESOURCE_MANAGER_ENDPOINT=$(az cloud show --query endpoints.resourceManager --output tsv --only-show-errors)
	METADATA_HOSTNAME="${RESOURCE_MANAGER_ENDPOINT#https://}"
	export ARM_METADATA_HOSTNAME="${METADATA_HOSTNAME%/}"
	# The emulator applies role assignments immediately, so the roles need no propagation wait.
	RBAC_PROPAGATION_DELAY="0s"
	echo "Active cloud is [$ACTIVE_CLOUD]: Terraform targets the emulator at [$RESOURCE_MANAGER_ENDPOINT]"
else
	# Cleared rather than merely not set: a value inherited from an earlier emulator deployment in the same shell would
	# keep the provider doing metadata discovery against the emulator while the CLI is on Azure.
	unset ARM_METADATA_HOSTNAME
	echo "Active cloud is [$ACTIVE_CLOUD]: Terraform targets Azure subscription [$ARM_SUBSCRIPTION_ID]"
fi

# Resolve the object id of the deploying principal. azurerm_key_vault_key, azurerm_key_vault_secret and
# azurerm_key_vault_certificate write through the Key Vault data plane, so on Azure the principal running terraform
# apply needs the Key Vault Crypto, Secrets and Certificates Officer roles on the vault; the configuration assigns them
# when the id is known. The lookup goes through Microsoft Graph; when it fails the assignments are skipped and the roles
# become a prerequisite (see the README).
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
else
	echo "WARNING: could not resolve the object id of the deploying principal [$ACCOUNT_USER_NAME]; the Key Vault Crypto, Secrets and Certificates Officer roles on the key vault must already be assigned to it"
	DEPLOYER_OBJECT_ID=""
fi

echo "Initializing Terraform..."
terraform init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "administrator_login=$ADMIN_USER" \
	-var "administrator_login_password=$ADMIN_PASSWORD" \
	-var "sql_database_username=$DATABASE_USER_NAME" \
	-var "sql_database_password=$DATABASE_USER_PASSWORD" \
	-var "secret_name=$SECRET_NAME" \
	-var "deployer_object_id=$DEPLOYER_OBJECT_ID" \
	-var "deployer_principal_type=$DEPLOYER_PRINCIPAL_TYPE" \
	-var "rbac_propagation_delay=$RBAC_PROPAGATION_DELAY"

if [[ $? != 0 ]]; then
	echo "Terraform plan failed. Exiting."
	exit 1
fi

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
terraform apply -auto-approve tfplan

if [[ $? != 0 ]]; then
	echo "Terraform apply failed. Exiting."
	exit 1
fi

# Get the output values
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
WEB_APP_NAME=$(terraform output -raw web_app_name)
SQL_SERVER_NAME=$(terraform output -raw sql_server_name)
SQL_DATABASE_NAME=$(terraform output -raw sql_database_name)

if [[ -z "$WEB_APP_NAME" || -z "$SQL_SERVER_NAME" || -z "$SQL_DATABASE_NAME" ]]; then
	echo "Web App Name, SQL Server Name, or SQL Database Name is empty. Exiting."
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

# Create server-level login
echo "Creating login [$DATABASE_USER_NAME] at server level..."
sqlcmd -S "$SQL_SERVER_FQDN" \
	-d master \
	-U "$ADMIN_USER" \
	-P "$ADMIN_PASSWORD" \
	-C \
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
	-C \
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
	-C \
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
	-C \
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
	-C \
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
	-C \
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
	-C \
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
zip -r "$ZIPFILE" app.py gunicorn.conf.py activities.py database.py certificates.py static templates requirements.txt

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

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi
