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
MONGODB_DATABASE_NAME="sampledb"
COLLECTION_NAME="activities"
INDEXES='[{"key":{"keys":["username"]}},{"key":{"keys":["activity"]}},{"key":{"keys":["timestamp"]}}]'
SHARD="username"
THROUGHPUT=400
RUNTIME="python"
RUNTIME_VERSION="3.12"
AZURE_CLIENT_ID="211c8652-a609-453a-bdb3-eda8405f5c4c"
AZURE_CLIENT_SECRET="D768Q~WrZz6STebgsEu28-.sLQx2kEhTpmpnLcPw"
AZURE_TENANT_ID="24083153-e8cb-43bf-a098-be24dc3668f7"
AZURE_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
USERNAME="Paolo"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Create a resource group
echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
az group create \
	--name $RESOURCE_GROUP_NAME \
	--location $LOCATION \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "Resource group [$RESOURCE_GROUP_NAME] created successfully."
else
	echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
	exit 1
fi

# Create a CosmosDB account with MongoDB kind
echo "Creating [$COSMOSDB_ACCOUNT_NAME] CosmosDB account in the [$RESOURCE_GROUP_NAME] resource group..."
azlocal cosmosdb create \
	--name $COSMOSDB_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--locations regionName=$LOCATION \
	--kind MongoDB \
	--default-consistency-level Session \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "[$COSMOSDB_ACCOUNT_NAME] CosmosDB account successfully created in the [$RESOURCE_GROUP_NAME] resource group"
else
	echo "Failed to create [$COSMOSDB_ACCOUNT_NAME] CosmosDB account in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Retrieve document endpoint
DOCUMENT_ENDPOINT=$(azlocal cosmosdb show \
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
azlocal cosmosdb mongodb database create \
	--account-name $COSMOSDB_ACCOUNT_NAME \
	--name $MONGODB_DATABASE_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--output json \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "[$MONGODB_DATABASE_NAME] MongoDB database successfully created in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account"
else
	echo "Failed to create [$MONGODB_DATABASE_NAME] MongoDB database in the [$COSMOSDB_ACCOUNT_NAME] CosmosDB account"
	exit 1
fi

# Create a MongoDB database collection
echo "Creating [$COLLECTION_NAME] collection in the [$MONGODB_DATABASE_NAME] MongoDB database..."
azlocal cosmosdb mongodb collection create \
	--account-name $COSMOSDB_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--database-name $MONGODB_DATABASE_NAME \
	--name $COLLECTION_NAME \
	--idx "$INDEXES" \
	--shard $SHARD \
	--throughput $THROUGHPUT \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "[$COLLECTION_NAME] collection successfully created in the [$MONGODB_DATABASE_NAME] MongoDB database"
else
	echo "Failed to create [$COLLECTION_NAME] collection in the [$MONGODB_DATABASE_NAME] MongoDB database"
	exit 1
fi

# Create App Service Plan
echo "Creating App Service Plan [$APP_SERVICE_PLAN_NAME]..."
azlocal appservice plan create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_SERVICE_PLAN_NAME" \
	--location "$LOCATION" \
	--sku "$APP_SERVICE_PLAN_SKU" \
	--is-linux \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "App Service Plan [$APP_SERVICE_PLAN_NAME] created successfully."
else
	echo "Failed to create App Service Plan [$APP_SERVICE_PLAN_NAME]."
	exit 1
fi

# Create the web app
echo "Creating web app [$WEB_APP_NAME]..."
azlocal webapp create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--plan "$APP_SERVICE_PLAN_NAME" \
	--name "$WEB_APP_NAME" \
	--runtime "$RUNTIME:$RUNTIME_VERSION" \
	--only-show-errors 1> /dev/null

if [ $? -eq 0 ]; then
	echo "Web app [$WEB_APP_NAME] created successfully."
else
	echo "Failed to create web app [$WEB_APP_NAME]."
	exit 1
fi

# Set web app settings
echo "Setting web app settings for [$WEB_APP_NAME]..."
az functionapp config appsettings set \
	--name $WEB_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	AZURE_CLIENT_ID="$AZURE_CLIENT_ID" \
	AZURE_CLIENT_SECRET="$AZURE_CLIENT_SECRET" \
	AZURE_TENANT_ID="$AZURE_TENANT_ID" \
	AZURE_SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID" \
	COSMOSDB_BASE_URL="$DOCUMENT_ENDPOINT" \
	COSMOSDB_DATABASE_NAME="$MONGODB_DATABASE_NAME" \
	COSMOSDB_COLLECTION_NAME="$COLLECTION_NAME" \
	USERNAME="$USERNAME" \
	--only-show-errors 1> /dev/null

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
zip -r "$ZIPFILE" app.py cosmosdb.py static templates requirements.txt

# Deploy the web app
azlocal webapp deploy \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$WEB_APP_NAME" \
  --src-path planner_website.zip \
  --type zip \
  --async true

# Remove the zip package of the web app
rm "$ZIPFILE"
