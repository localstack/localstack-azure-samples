#!/bin/bash

# Variables
PREFIX='cayado'
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
DEPLOY_APP=1

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit
# Validates if the resource group exists in the subscription, if not creates it
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	# Create the resource group
	az group create \
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
		az deployment group what-if \
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
		output=$(az deployment group validate \
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
if DEPLOYMENT_OUTPUTS=$(az deployment group create \
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
	--query 'properties.outputs' \
	--output json); then
	# Extract only the JSON portion (everything from first { to the end)
	DEPLOYMENT_JSON=$(echo "$DEPLOYMENT_OUTPUTS" | sed -n '/{/,$ p')
	echo "Bicep template [$TEMPLATE] deployed successfully. Outputs:"
	echo "$DEPLOYMENT_JSON" | jq .
	APP_SERVICE_PLAN_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.appServicePlanName.value')
	WEB_APP_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.webAppName.value')
	SQL_SERVER_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.sqlServerName.value')
	SQL_DATABASE_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.sqlDatabaseName.value')
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
zip -r "$ZIPFILE" app.py activities.py certificates.py database.py static templates requirements.txt

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
