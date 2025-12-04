#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="S1"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
COSMOSDB_ACCOUNT_NAME="${PREFIX}-mongodb-${SUFFIX}"
MONGODB_API_VERSION="7.0"
MONGODB_DATABASE_NAME="sampledb"
COLLECTION_NAME="activities"
INDEXES='[{"key":{"keys":["_id"]}},{"key":{"keys":["username"]}},{"key":{"keys":["activity"]}},{"key":{"keys":["timestamp"]}}]'
SHARD="username"
THROUGHPUT=400
RUNTIME="python"
RUNTIME_VERSION="3.13"
LOGIN_NAME="paolo"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"
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

# Create a resource group
echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
$AZ group create \
	--name $RESOURCE_GROUP_NAME \
	--location $LOCATION \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Resource group [$RESOURCE_GROUP_NAME] created successfully."
else
	echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
	exit 1
fi

# Create a CosmosDB account with MongoDB kind
echo "Creating [$COSMOSDB_ACCOUNT_NAME] CosmosDB account in the [$RESOURCE_GROUP_NAME] resource group..."
$AZ cosmosdb create \
	--name $COSMOSDB_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--locations regionName=$LOCATION \
	--kind MongoDB \
	--server-version $MONGODB_API_VERSION \
	--default-consistency-level Session \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "[$COSMOSDB_ACCOUNT_NAME] CosmosDB account successfully created in the [$RESOURCE_GROUP_NAME] resource group"
else
	echo "Failed to create [$COSMOSDB_ACCOUNT_NAME] CosmosDB account in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Retrieve document endpoint
DOCUMENT_ENDPOINT=$($AZ cosmosdb show \
	--name $COSMOSDB_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "documentEndpoint" \
	--output tsv \
	--only-show-errors)

if [ -n "$DOCUMENT_ENDPOINT" ]; then
	echo "Document endpoint retrieved successfully: $DOCUMENT_ENDPOINT"
else
	echo "Failed to retrieve document endpoint."
	exit 1
fi

# Create MongoDB database
echo "Creating [$MONGODB_DATABASE_NAME] MongoDB database in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account..."
$AZ cosmosdb mongodb database create \
	--account-name $COSMOSDB_ACCOUNT_NAME \
	--name $MONGODB_DATABASE_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--output json \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "[$MONGODB_DATABASE_NAME] MongoDB database successfully created in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account"
else
	echo "Failed to create [$MONGODB_DATABASE_NAME] MongoDB database in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account"
	exit 1
fi

# Create a MongoDB database collection
echo "Creating [$COLLECTION_NAME] collection in the [$MONGODB_DATABASE_NAME] MongoDB database..."
$AZ cosmosdb mongodb collection create \
	--account-name $COSMOSDB_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--database-name $MONGODB_DATABASE_NAME \
	--name $COLLECTION_NAME \
	--idx "$INDEXES" \
	--shard $SHARD \
	--throughput $THROUGHPUT \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "[$COLLECTION_NAME] collection successfully created in the [$MONGODB_DATABASE_NAME] MongoDB database"
else
	echo "Failed to create [$COLLECTION_NAME] collection in the [$MONGODB_DATABASE_NAME] MongoDB database"
	exit 1
fi

# List CosmosDB connection strings
echo "Listing connection strings for CosmosDB account [$COSMOSDB_ACCOUNT_NAME]..."
COSMOSDB_CONNECTION_STRING=$($AZ cosmosdb keys list \
	--name $COSMOSDB_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--type connection-strings \
	--query "connectionStrings[0].connectionString" \
	--output tsv)

if [ $? -eq 0 ]; then
	echo "CosmosDB connection strings retrieved successfully."
	echo "Connection String: $COSMOSDB_CONNECTION_STRING"
else
	echo "Failed to retrieve CosmosDB connection strings."
fi

# Create App Service Plan
echo "Creating App Service Plan [$APP_SERVICE_PLAN_NAME]..."
$AZ appservice plan create \
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
$AZ webapp create \
	--resource-group "$RESOURCE_GROUP_NAME" \
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

# Set web app settings
echo "Setting web app settings for [$WEB_APP_NAME]..."
$AZ webapp config appsettings set \
	--name $WEB_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	COSMOSDB_CONNECTION_STRING="$COSMOSDB_CONNECTION_STRING" \
	COSMOSDB_DATABASE_NAME="$MONGODB_DATABASE_NAME" \
	COSMOSDB_COLLECTION_NAME="$COLLECTION_NAME" \
	LOGIN_NAME="$LOGIN_NAME" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app settings for [$WEB_APP_NAME] set successfully."
else
	echo "Failed to set web app settings for [$WEB_APP_NAME]."
	exit 1
fi

# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py mongodb.py static templates requirements.txt

# List the contents of the zip package
echo "Contents of the zip package [$ZIPFILE]:"
unzip -l "$ZIPFILE"

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
echo "Using standard $AZ webapp deploy command for AzureCloud environment."
$AZ webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi