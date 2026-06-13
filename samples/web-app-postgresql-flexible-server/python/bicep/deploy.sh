#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOCATION="westeurope"
VALIDATE_TEMPLATE=1
USE_WHAT_IF=0
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
PG_ADMIN_USER="pgadmin"
PG_ADMIN_PASSWORD="P@ssw0rd1234!"
PG_APP_USER="testuser"
PG_APP_PASSWORD="TestP@ssw0rd123"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"

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
		--only-show-errors 1> /dev/null

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
			pgAdminPassword="$PG_ADMIN_PASSWORD" \
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
			pgAdminPassword="$PG_ADMIN_PASSWORD" \
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
	pgAdminPassword="$PG_ADMIN_PASSWORD" \
	--query 'properties.outputs' -o json); then
	# Extract only the JSON portion (everything from first { to the end)
	DEPLOYMENT_JSON=$(echo "$DEPLOYMENT_OUTPUTS" | sed -n '/{/,$ p')
	echo "Bicep template [$TEMPLATE] deployed successfully. Outputs:"
	echo "$DEPLOYMENT_JSON" | jq .
	WEB_APP_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.webAppName.value')
	POSTGRES_SERVER_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.postgresServerName.value')
	POSTGRES_FQDN_FULL=$(echo "$DEPLOYMENT_JSON" | jq -r '.postgresFqdn.value')
	DATABASE_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.databaseName.value')
	echo "Deployment details:"
	echo "Web App Name: $WEB_APP_NAME"
	echo "PostgreSQL Server Name: $POSTGRES_SERVER_NAME"
	echo "PostgreSQL FQDN: $POSTGRES_FQDN_FULL"
	echo "Database Name: $DATABASE_NAME"
else
	echo "Failed to deploy Bicep template [$TEMPLATE]"
	exit 1
fi

if [[ -z "$WEB_APP_NAME" || -z "$POSTGRES_SERVER_NAME" ]]; then
	echo "Web App Name or PostgreSQL Server Name is empty. Exiting."
	exit 1
fi

# Split host:port — the LocalStack emulator embeds the dynamically allocated TCP-proxy port
# directly in fullyQualifiedDomainName, mirroring the storage / container registry emulators.
# Real Azure returns just the bare host so PG_PORT defaults to 5432.
POSTGRES_FQDN="${POSTGRES_FQDN_FULL%%:*}"
if [[ "$POSTGRES_FQDN_FULL" == *:* ]]; then
	POSTGRES_PORT="${POSTGRES_FQDN_FULL##*:}"
else
	POSTGRES_PORT=5432
fi
echo "PostgreSQL host = $POSTGRES_FQDN, port = $POSTGRES_PORT"

# Create application role [$PG_APP_USER] on the PostgreSQL flexible server
echo "Creating login [$PG_APP_USER] on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."
PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_ADMIN_USER" \
	--dbname=postgres \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "DO \$\$
BEGIN
	IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$PG_APP_USER') THEN
		CREATE ROLE \"$PG_APP_USER\" WITH LOGIN PASSWORD '$PG_APP_PASSWORD';
	END IF;
END
\$\$;"

if [ $? -eq 0 ]; then
	echo "Login [$PG_APP_USER] created successfully"
else
	echo "Failed to create login [$PG_APP_USER]"
	exit 1
fi

# Grant CONNECT on the database to [$PG_APP_USER]
echo "Granting CONNECT on [$DATABASE_NAME] to [$PG_APP_USER]..."
PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_ADMIN_USER" \
	--dbname=postgres \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "GRANT CONNECT ON DATABASE \"$DATABASE_NAME\" TO \"$PG_APP_USER\";"

if [ $? -eq 0 ]; then
	echo "CONNECT granted successfully to [$PG_APP_USER]"
else
	echo "Failed to grant CONNECT to [$PG_APP_USER]"
	exit 1
fi

# Grant schema privileges to [$PG_APP_USER]
echo "Granting schema privileges on [$DATABASE_NAME] to [$PG_APP_USER]..."
PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_ADMIN_USER" \
	--dbname="$DATABASE_NAME" \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "GRANT USAGE, CREATE ON SCHEMA public TO \"$PG_APP_USER\";
		ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"$PG_APP_USER\";
		ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"$PG_APP_USER\";"

if [ $? -eq 0 ]; then
	echo "Schema privileges granted successfully to [$PG_APP_USER]"
else
	echo "Failed to grant schema privileges to [$PG_APP_USER]"
	exit 1
fi

# Test connection
echo "Testing connection with user [$PG_APP_USER]..."
PGPASSWORD="$PG_APP_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_APP_USER" \
	--dbname="$DATABASE_NAME" \
	--no-password \
	-c "SELECT current_user, current_database(), now();"

if [ $? -eq 0 ]; then
	echo "Connection test successful with user [$PG_APP_USER]"
else
	echo "Connection test failed with user [$PG_APP_USER]"
	exit 1
fi

# Create [activities] table
echo "Creating [activities] table in the [$DATABASE_NAME] database..."
PGPASSWORD="$PG_APP_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_APP_USER" \
	--dbname="$DATABASE_NAME" \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "CREATE TABLE IF NOT EXISTS activities (
			id           TEXT PRIMARY KEY,
			username     TEXT NOT NULL,
			activity     TEXT NOT NULL,
			created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
		CREATE INDEX IF NOT EXISTS idx_activities_username ON activities(username);
		CREATE INDEX IF NOT EXISTS idx_activities_created_at ON activities(created_at DESC);"

if [ $? -eq 0 ]; then
	echo "[activities] table created successfully"
else
	echo "Failed to create [activities] table"
	exit 1
fi

# Insert sample data
echo "Inserting sample data into [activities] table..."
PGPASSWORD="$PG_APP_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_APP_USER" \
	--dbname="$DATABASE_NAME" \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "INSERT INTO activities (id, username, activity) VALUES
			(md5('paolo_pisa_seed'), 'paolo', 'Visit the Leaning Tower in Pisa'),
      (md5('paolo_volterra_seed'), 'paolo', 'Explore Etruscan walls in Volterra'),
      (md5('paolo_san_gimignano_seed'), 'paolo', 'Climb Torre Grossa in San Gimignano'),
      (md5('paolo_siena_seed'), 'paolo', 'Walk across Piazza del Campo in Siena'),
      (md5('paolo_montalcino_seed'), 'paolo', 'Taste Brunello wine in Montalcino'),
      (md5('paolo_pienza_seed'), 'paolo', 'Sample Pecorino cheese in Pienza'),
      (md5('paolo_florence_seed'), 'paolo', 'Admire Michelangelo''s David in Florence'),
      (md5('paolo_viareggio_beach_seed'), 'paolo', 'Relax by the beach in Viareggio'),
      (md5('paolo_viareggio_promenade_seed'), 'paolo', 'Stroll along the Viareggio promenade')
		ON CONFLICT (id) DO NOTHING;"

if [ $? -eq 0 ]; then
	echo "Sample data inserted successfully into [activities] table"
else
	echo "Failed to insert sample data into [activities] table"
	exit 1
fi

# Query sample data
echo "Querying sample data from [activities] table..."
PGPASSWORD="$PG_APP_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_APP_USER" \
	--dbname="$DATABASE_NAME" \
	--no-password \
	-c "SELECT * FROM activities;"

if [ $? -eq 0 ]; then
	echo "Sample data queried successfully from [activities] table"
else
	echo "Failed to query sample data from [activities] table"
	exit 1
fi

# Set PG_USER + PG_PASSWORD on the web app to point at the application role
echo "Setting PG_USER=[$PG_APP_USER] and PG_PASSWORD on the [$WEB_APP_NAME] web app..."
az webapp config appsettings set \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--settings PG_USER="$PG_APP_USER" PG_PASSWORD="$PG_APP_PASSWORD" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "PG_USER and PG_PASSWORD set successfully on the [$WEB_APP_NAME] web app"
else
	echo "Failed to set PG_USER and PG_PASSWORD on the [$WEB_APP_NAME] web app"
	exit 1
fi

# Print the application settings of the web app
echo "Retrieving application settings for web app [$WEB_APP_NAME]..."
az webapp config appsettings list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME"

# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py database.py gunicorn.conf.py static templates requirements.txt

# Deploy the web app
# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
az webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Print the list of resources in the resource group
echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table 
