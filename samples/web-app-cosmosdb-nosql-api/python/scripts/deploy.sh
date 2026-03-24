#!/bin/bash


PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="S1"
WEB_APP_NAME="${PREFIX}-webapp-nosql-${SUFFIX}"
COSMOSDB_ACCOUNT_NAME="${PREFIX}-nosqlapi-${SUFFIX}"
ZIPFILE="${WEB_APP_NAME}.zip"

RANDOM_SUFFIX=$(echo $RANDOM)
NEW_DB_NAME="vacationplanner_${RANDOM_SUFFIX}"
AZURECOSMOSDB_DATABASENAME=$NEW_DB_NAME
AZURECOSMOSDB_CONTAINERNAME="activities_${RANDOM_SUFFIX}"
AURECOSMOSDB_PARTITION_KEY="/username"

# azlocal start-interception

# Validates if the resource group exists in the subscription, if not creates it
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists"
	echo "Creating resource group [$RESOURCE_GROUP_NAME]..."

	# Create the resource group
    az group create \
        --name $RESOURCE_GROUP_NAME \
        --location $LOCATION \
        --only-show-errors 1> /dev/null \

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created."
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
		exit
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists."
fi

echo "Create CosmosDB NoSQL Account"
    export AZURECOSMOSDB_ENDPOINT=$(az cosmosdb create \
        --resource-group $RESOURCE_GROUP_NAME \
        --name $WEB_APP_NAME \
        --locations regionName=$LOCATION \
        --query "documentEndpoint" \
        --output tsv)

echo "Account created"
echo "AZURECOSMOSDB_ENDPOINT set to $AZURECOSMOSDB_ENDPOINT"

echo "Create CosmosDB NoSQL Database"
az cosmosdb sql database create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $AZURECOSMOSDB_DATABASENAME \
    --account-name $WEB_APP_NAME

echo "Create CosmosDB NoSQL Container"
az cosmosdb sql container create \
    --resource-group $RESOURCE_GROUP_NAME \
    --account-name $WEB_APP_NAME \
    --database-name $AZURECOSMOSDB_DATABASENAME \
    --name $AZURECOSMOSDB_CONTAINERNAME \
    --partition-key-path $AURECOSMOSDB_PARTITION_KEY \
    --throughput 400

echo "Fetching DB Account primary master key"
export AZURECOSMOSDB_PRIMARY_KEY=$(az cosmosdb keys list \
        --resource-group $RESOURCE_GROUP_NAME \
        --name $WEB_APP_NAME \
        --query "primaryMasterKey" \
        --output tsv)
echo "Primary master key is $AZURECOSMOSDB_PRIMARY_KEY"

echo "Creating App service"
az appservice plan create --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP_NAME --sku B1 --is-linux
echo "App service created"

echo "Creating Web App"
az webapp create --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP_NAME --plan $WEB_APP_NAME --runtime PYTHON:3.13
echo "Web App created"

echo "Configure appsettings environment variables"
az webapp config appsettings set \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $WEB_APP_NAME \
    --settings AZURECOSMOSDB_ENDPOINT=$AZURECOSMOSDB_ENDPOINT \
               AZURECOSMOSDB_DATABASENAME=$AZURECOSMOSDB_DATABASENAME \
               AZURECOSMOSDB_CONTAINERNAME=$AZURECOSMOSDB_CONTAINERNAME \
               AZURECOSMOSDB_PRIMARY_KEY=$AZURECOSMOSDB_PRIMARY_KEY

# Print the application settings of the web app
echo "Retrieving application settings for web app [$WEB_APP_NAME]..."
az webapp config appsettings list \
	--resource-group $RESOURCE_GROUP_NAME \
	--name $WEB_APP_NAME

# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py cosmosdb_client.py static templates requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
echo "Using az webapp deploy command for LocalStack emulator environment."
az webapp deploy \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $WEB_APP_NAME \
    --src-path ${ZIPFILE} \
    --type zip \
    --async true

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi
