#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP='rg-pgflex'
SERVER_NAME='pgflex-sample'
LOCATION='westeurope'
ADMIN_USER='pgadmin'
ADMIN_PASSWORD='P@ssw0rd12345!'
PG_VERSION='16'
STORAGE_SIZE=32
PRIMARY_DB='sampledb'
SECONDARY_DB='analyticsdb'
APP_SERVICE_PLAN_NAME="${PREFIX}-pgflex-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="S1"
WEB_APP_NAME="${PREFIX}-pgflex-webapp-${SUFFIX}"
RUNTIME="python"
RUNTIME_VERSION="3.13"
ZIPFILE="notes_app.zip"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAMPLE_DIR="$(cd "$CURRENT_DIR/.." && pwd)"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

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

# Create resource group
echo "Creating resource group [$RESOURCE_GROUP]..."
$AZ group create \
	--name "$RESOURCE_GROUP" \
	--location "$LOCATION" \
	--output table

if [[ $? != 0 ]]; then
	echo "Failed to create resource group. Exiting."
	exit 1
fi

# Create PostgreSQL Flexible Server
# Note: We use 'az rest' to call the management API directly because the
# 'az postgres flexible-server create' CLI command performs a SKU availability
# pre-check that fails on LocalStack (capabilities endpoint returns no SKUs).
# Using the REST API bypasses this client-side validation.
SUBSCRIPTION_ID=$($AZ account show --query id --output tsv)
echo "Creating PostgreSQL Flexible Server [$SERVER_NAME]..."
$AZ rest \
	--method PUT \
	--url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DBforPostgreSQL/flexibleServers/${SERVER_NAME}?api-version=2024-08-01" \
	--body "{
		\"location\": \"${LOCATION}\",
		\"properties\": {
			\"version\": \"${PG_VERSION}\",
			\"administratorLogin\": \"${ADMIN_USER}\",
			\"administratorLoginPassword\": \"${ADMIN_PASSWORD}\",
			\"storage\": { \"storageSizeGB\": ${STORAGE_SIZE} },
			\"createMode\": \"Default\"
		},
		\"sku\": {
			\"name\": \"Standard_B1ms\",
			\"tier\": \"Burstable\"
		}
	}" \
	--output table

if [[ $? != 0 ]]; then
	echo "Failed to create PostgreSQL Flexible Server. Exiting."
	exit 1
fi

echo "PostgreSQL Flexible Server [$SERVER_NAME] created successfully."

# Wait for the server to be fully ready.
# The REST API returns immediately but the PostgreSQL container may still
# be initializing (admin role creation, etc.).
echo "Waiting for server to be fully provisioned..."
for i in $(seq 1 30); do
	STATE=$($AZ postgres flexible-server show \
		--name "$SERVER_NAME" \
		--resource-group "$RESOURCE_GROUP" \
		--query "state" \
		--output tsv 2>/dev/null)
	if [[ "$STATE" == "Ready" ]]; then
		echo "Server is ready."
		break
	fi
	echo "  Server state: ${STATE:-unknown} (attempt $i/30)"
	sleep 5
done

# Create primary database
echo "Creating database [$PRIMARY_DB]..."
$AZ postgres flexible-server db create \
	--server-name "$SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--database-name "$PRIMARY_DB" \
	--charset "UTF8" \
	--collation "en_US.utf8" \
	--output table

if [[ $? != 0 ]]; then
	echo "Failed to create database [$PRIMARY_DB]. Exiting."
	exit 1
fi

# Create secondary database
echo "Creating database [$SECONDARY_DB]..."
$AZ postgres flexible-server db create \
	--server-name "$SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--database-name "$SECONDARY_DB" \
	--charset "UTF8" \
	--collation "en_US.utf8" \
	--output table

if [[ $? != 0 ]]; then
	echo "Failed to create database [$SECONDARY_DB]. Exiting."
	exit 1
fi

# Create firewall rules
# Note: The firewall-rule subcommand uses --name/-n for the server name
# and --rule-name/-r for the rule name (unlike db create which uses --server-name).
echo "Creating firewall rule [allow-all]..."
$AZ postgres flexible-server firewall-rule create \
	--rule-name "allow-all" \
	--name "$SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--start-ip-address "0.0.0.0" \
	--end-ip-address "255.255.255.255" \
	--output table

echo "Creating firewall rule [corporate-network]..."
$AZ postgres flexible-server firewall-rule create \
	--rule-name "corporate-network" \
	--name "$SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--start-ip-address "10.0.0.1" \
	--end-ip-address "10.0.255.255" \
	--output table

echo "Creating firewall rule [vpn-access]..."
$AZ postgres flexible-server firewall-rule create \
	--rule-name "vpn-access" \
	--name "$SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--start-ip-address "192.168.100.1" \
	--end-ip-address "192.168.100.254" \
	--output table

# Retrieve the FQDN of the server
echo "Retrieving the FQDN of the [$SERVER_NAME] PostgreSQL Flexible Server..."
SERVER_FQDN=$($AZ postgres flexible-server show \
	--name "$SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--query "fullyQualifiedDomainName" \
	--output tsv)

if [ -z "$SERVER_FQDN" ]; then
	echo "Failed to retrieve the FQDN of the PostgreSQL Flexible Server"
	exit 1
fi

echo "Server FQDN: $SERVER_FQDN"

# Create App Service Plan
echo "Creating App Service Plan [$APP_SERVICE_PLAN_NAME]..."
$AZ appservice plan create \
	--resource-group "$RESOURCE_GROUP" \
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
$AZ webapp create \
	--resource-group "$RESOURCE_GROUP" \
	--plan "$APP_SERVICE_PLAN_NAME" \
	--name "$WEB_APP_NAME" \
	--runtime "$RUNTIME:$RUNTIME_VERSION" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app [$WEB_APP_NAME] created successfully."
else
	echo "Failed to create web app [$WEB_APP_NAME]."
	exit 1
fi

# Set web app settings with PostgreSQL connection details
echo "Setting web app settings for [$WEB_APP_NAME]..."
$AZ webapp config appsettings set \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--settings \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	PG_HOST="$SERVER_FQDN" \
	PG_USER="$ADMIN_USER" \
	PG_PASSWORD="$ADMIN_PASSWORD" \
	PG_DATABASE="$PRIMARY_DB" \
	PG_PORT="5432" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app settings for [$WEB_APP_NAME] set successfully."
else
	echo "Failed to set web app settings for [$WEB_APP_NAME]."
	exit 1
fi

# Change to the notes-app source directory
cd "$SAMPLE_DIR/src/notes-app" || exit

# Remove any existing zip package
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the notes app..."
zip -r "$ZIPFILE" app.py requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
$AZ webapp deploy \
	--resource-group "$RESOURCE_GROUP" \
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

# Clean up zip file
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Get web app URL
WEB_APP_URL=$($AZ webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--query "defaultHostName" \
	--output tsv)

echo ""
echo "=== Deployment Complete ==="
echo "Resource Group:   $RESOURCE_GROUP"
echo "Server Name:      $SERVER_NAME"
echo "Server FQDN:      $SERVER_FQDN"
echo "Primary DB:       $PRIMARY_DB"
echo "Secondary DB:     $SECONDARY_DB"
echo "Web App Name:     $WEB_APP_NAME"
echo "Web App URL:      https://$WEB_APP_URL"
echo ""
