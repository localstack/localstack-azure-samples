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
MYSQL_ADMIN_USER="${MYSQL_ADMIN_USER:-myadmin}"
MYSQL_ADMIN_PASSWORD="${MYSQL_ADMIN_PASSWORD:-P@ssw0rd1234!}"
MYSQL_APP_USER="${MYSQL_APP_USER:-testuser}"
MYSQL_APP_PASSWORD="${MYSQL_APP_PASSWORD:-TestP@ssw0rd123}"
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
			mysqlAdminPassword="$MYSQL_ADMIN_PASSWORD" \
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
			mysqlAdminPassword="$MYSQL_ADMIN_PASSWORD" \
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
	mysqlAdminPassword="$MYSQL_ADMIN_PASSWORD" \
	--query 'properties.outputs' -o json); then
	# Extract only the JSON portion (everything from first { to the end)
	DEPLOYMENT_JSON=$(echo "$DEPLOYMENT_OUTPUTS" | sed -n '/{/,$ p')
	echo "Bicep template [$TEMPLATE] deployed successfully. Outputs:"
	echo "$DEPLOYMENT_JSON" | jq .
	WEB_APP_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.webAppName.value')
	MYSQL_SERVER_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.mysqlServerName.value')
	MYSQL_FQDN_FULL=$(echo "$DEPLOYMENT_JSON" | jq -r '.mysqlFqdn.value')
	DATABASE_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.databaseName.value')
	echo "Deployment details:"
	echo "Web App Name: $WEB_APP_NAME"
	echo "MySQL Server Name: $MYSQL_SERVER_NAME"
	echo "MySQL FQDN: $MYSQL_FQDN_FULL"
	echo "Database Name: $DATABASE_NAME"
else
	echo "Failed to deploy Bicep template [$TEMPLATE]"
	exit 1
fi

if [[ -z "$WEB_APP_NAME" || -z "$MYSQL_SERVER_NAME" ]]; then
	echo "Web App Name or MySQL Server Name is empty. Exiting."
	exit 1
fi

# Split host:port — the LocalStack emulator embeds the dynamically allocated TCP-proxy port
# directly in fullyQualifiedDomainName, mirroring the storage / container registry emulators.
# Real Azure returns just the bare host so MYSQL_PORT defaults to 3306.
MYSQL_FQDN="${MYSQL_FQDN_FULL%%:*}"
if [[ "$MYSQL_FQDN_FULL" == *:* ]]; then
	MYSQL_PORT="${MYSQL_FQDN_FULL##*:}"
else
	MYSQL_PORT=3306
fi
echo "MySQL host = $MYSQL_FQDN, port = $MYSQL_PORT"

# Create application user [$MYSQL_APP_USER] on the MySQL flexible server
echo "Creating login [$MYSQL_APP_USER] on the [$MYSQL_SERVER_NAME] MySQL flexible server..."
MYSQL_PWD="$MYSQL_ADMIN_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_ADMIN_USER" \
	--protocol=TCP \
	-e "CREATE USER IF NOT EXISTS '$MYSQL_APP_USER'@'%' IDENTIFIED BY '$MYSQL_APP_PASSWORD';
		GRANT ALL PRIVILEGES ON \`$DATABASE_NAME\`.* TO '$MYSQL_APP_USER'@'%';
		FLUSH PRIVILEGES;"

if [ $? -eq 0 ]; then
	echo "Login [$MYSQL_APP_USER] created successfully"
else
	echo "Failed to create login [$MYSQL_APP_USER]"
	exit 1
fi

# Test connection
echo "Testing connection with user [$MYSQL_APP_USER]..."
MYSQL_PWD="$MYSQL_APP_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_APP_USER" \
	--protocol=TCP \
	--database="$DATABASE_NAME" \
	-e "SELECT CURRENT_USER() AS user_name, DATABASE() AS db_name, NOW() AS server_time;"

if [ $? -eq 0 ]; then
	echo "Connection test successful with user [$MYSQL_APP_USER]"
else
	echo "Connection test failed with user [$MYSQL_APP_USER]"
	exit 1
fi

# Create [activities] table
echo "Creating [activities] table in the [$DATABASE_NAME] database..."
MYSQL_PWD="$MYSQL_APP_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_APP_USER" \
	--protocol=TCP \
	--database="$DATABASE_NAME" \
	-e "CREATE TABLE IF NOT EXISTS activities (
			id           VARCHAR(32)  NOT NULL,
			username     VARCHAR(255) NOT NULL,
			activity     TEXT         NOT NULL,
			created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			INDEX idx_activities_username (username),
			INDEX idx_activities_created_at (created_at DESC)
		);"

if [ $? -eq 0 ]; then
	echo "[activities] table created successfully"
else
	echo "Failed to create [activities] table"
	exit 1
fi

# Insert sample data
echo "Inserting sample data into [activities] table..."
MYSQL_PWD="$MYSQL_APP_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_APP_USER" \
	--protocol=TCP \
	--database="$DATABASE_NAME" \
	-e "INSERT IGNORE INTO activities (id, username, activity) VALUES
			(MD5('paolo_pisa_seed'), 'paolo', 'Visit the Leaning Tower in Pisa'),
			(MD5('paolo_volterra_seed'), 'paolo', 'Explore Etruscan walls in Volterra'),
			(MD5('paolo_san_gimignano_seed'), 'paolo', 'Climb Torre Grossa in San Gimignano'),
			(MD5('paolo_siena_seed'), 'paolo', 'Walk across Piazza del Campo in Siena'),
			(MD5('paolo_montalcino_seed'), 'paolo', 'Taste Brunello wine in Montalcino'),
			(MD5('paolo_pienza_seed'), 'paolo', 'Sample Pecorino cheese in Pienza'),
			(MD5('paolo_florence_seed'), 'paolo', 'Admire Michelangelo''s David in Florence'),
			(MD5('paolo_viareggio_beach_seed'), 'paolo', 'Relax by the beach in Viareggio'),
			(MD5('paolo_viareggio_promenade_seed'), 'paolo', 'Stroll along the Viareggio promenade');"

if [ $? -eq 0 ]; then
	echo "Sample data inserted successfully into [activities] table"
else
	echo "Failed to insert sample data into [activities] table"
	exit 1
fi

# Query sample data
echo "Querying sample data from [activities] table..."
MYSQL_PWD="$MYSQL_APP_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_APP_USER" \
	--protocol=TCP \
	--database="$DATABASE_NAME" \
	-e "SELECT * FROM activities;"

if [ $? -eq 0 ]; then
	echo "Sample data queried successfully from [activities] table"
else
	echo "Failed to query sample data from [activities] table"
	exit 1
fi

# Set MYSQL_USER + MYSQL_PASSWORD on the web app to point at the application user
echo "Setting MYSQL_USER=[$MYSQL_APP_USER] and MYSQL_PASSWORD on the [$WEB_APP_NAME] web app..."
az webapp config appsettings set \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--settings MYSQL_USER="$MYSQL_APP_USER" MYSQL_PASSWORD="$MYSQL_APP_PASSWORD" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "MYSQL_USER and MYSQL_PASSWORD set successfully on the [$WEB_APP_NAME] web app"
else
	echo "Failed to set MYSQL_USER and MYSQL_PASSWORD on the [$WEB_APP_NAME] web app"
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
