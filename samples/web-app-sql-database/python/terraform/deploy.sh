#!/bin/bash
echo "Skipping Terraform deployment (not yet updated for Key Vault integration)."
exit 0

# Variables
PREFIX='websql'
SUFFIX='test'
LOCATION='westeurope'
ADMIN_USER='sqladmin'
ADMIN_PASSWORD='P@ssw0rd1234!'
DATABASE_USER_NAME='testuser'
DATABASE_USER_PASSWORD='TestP@ssw0rd123'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"
DEPLOY_APP=1

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Determine environment
if command -v az >/dev/null 2>&1; then
	CLOUD_NAME=$(az cloud show --query name --output tsv 2>&1 || echo "")

	if [[ "$CLOUD_NAME" == "LocalStack" ]]; then
		ENVIRONMENT="LocalStack"
	elif [[ "$CLOUD_NAME" == "AzureCloud" ]]; then
		ENVIRONMENT="AzureCloud"
	else
		ENVIRONMENT="AzureCloud"
	fi
else
	ENVIRONMENT="AzureCloud"
fi

# Run terraform init and apply
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using tflocal and azlocal for LocalStack emulator environment."
	TERRAFORM="tflocal"

	# Log Azure auth environment variables before unsetting
	echo "[DEBUG] Azure auth env vars before unsetting:"
	echo "[DEBUG]   ARM_CLIENT_ID=${ARM_CLIENT_ID:-<not set>}"
	echo "[DEBUG]   ARM_CLIENT_SECRET=${ARM_CLIENT_SECRET:+<set but hidden>}${ARM_CLIENT_SECRET:-<not set>}"
	echo "[DEBUG]   ARM_TENANT_ID=${ARM_TENANT_ID:-<not set>}"
	echo "[DEBUG]   ARM_SUBSCRIPTION_ID=${ARM_SUBSCRIPTION_ID:-<not set>}"
	echo "[DEBUG]   AZURE_CLIENT_ID=${AZURE_CLIENT_ID:-<not set>}"
	echo "[DEBUG]   AZURE_TENANT_ID=${AZURE_TENANT_ID:-<not set>}"

	echo "[DEBUG] Azure auth env vars after unsetting: all cleared"
	AZ="azlocal"
else
	echo "Using standard terraform and az for AzureCloud environment."
	TERRAFORM="terraform"
	AZ="az"
fi

echo "[DEBUG] Cloud name: '$CLOUD_NAME', Environment: '$ENVIRONMENT', Tools: TERRAFORM=$TERRAFORM, AZ=$AZ"
echo "[DEBUG] TERRAFORM command location: $(which $TERRAFORM 2>/dev/null || echo 'not found')"

# Enable Terraform debug logging
export TF_LOG=DEBUG
export TF_LOG_PATH="$CURRENT_DIR/terraform-debug.log"
echo "[DEBUG] Checking what tflocal does..."echo "[DEBUG] tflocal version: $($TERRAFORM version 2>&1 | head -1)"echo "[DEBUG] Contents of current directory before init:"ls -la . 2>&1 | head -20
echo "[DEBUG] Terraform debug logging enabled: TF_LOG=DEBUG, TF_LOG_PATH=$TF_LOG_PATH"

echo "Initializing Terraform..."
$TERRAFORM init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
$TERRAFORM plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "administrator_login=$ADMIN_USER" \
	-var "administrator_login_password=$ADMIN_PASSWORD" \
	-var "sql_database_username=$DATABASE_USER_NAME" \
	-var "sql_database_password=$DATABASE_USER_PASSWORD"

if [[ $? != 0 ]]; then
	echo "Terraform plan failed. Exiting."
	echo "============================================================"
	echo "Last 100 lines of Terraform debug log:"
	echo "============================================================"
	tail -100 "$TF_LOG_PATH" 2>/dev/null || echo "Debug log not found"
	echo "============================================================"
	exit 1
fi

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
$TERRAFORM apply -auto-approve tfplan

if [[ $? != 0 ]]; then
	echo "Terraform apply failed. Exiting."
	exit 1
fi

# Get the output values
RESOURCE_GROUP_NAME=$($TERRAFORM output -raw resource_group_name)
WEB_APP_NAME=$($TERRAFORM output -raw web_app_name)
SQL_SERVER_NAME=$($TERRAFORM output -raw sql_server_name)
SQL_DATABASE_NAME=$($TERRAFORM output -raw sql_database_name)

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
