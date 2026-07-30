#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
DEPLOYMENT_NAME='multi-service-app'
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
WEBAPP_ZIPFILE='linklet_webapp.zip'
WORKER_ZIPFILE='linklet_worker.zip'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Get the current subscription
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

# Check if the resource group already exists
echo "Checking if [$RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_NAME] subscription..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_NAME] subscription"
	echo "Creating [$RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_NAME] subscription..."

	az group create --name $RESOURCE_GROUP_NAME --location "$LOCATION" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$RESOURCE_GROUP_NAME] resource group successfully created in the [$SUBSCRIPTION_NAME] subscription"
	else
		echo "Failed to create [$RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_NAME] subscription"
		exit 1
	fi
else
	echo "[$RESOURCE_GROUP_NAME] resource group already exists in the [$SUBSCRIPTION_NAME] subscription"
fi

# Generate the deployment secrets; main.bicepparam reads them from the environment
export POSTGRES_ADMIN_PASSWORD=$(openssl rand -hex 10)
export SIGN_KEY=$(openssl rand -hex 16)
export INTERNAL_TOKEN=$(openssl rand -hex 12)

# Validate the Bicep template
echo "Validating the [$TEMPLATE] Bicep template..."
az deployment group validate \
	--resource-group $RESOURCE_GROUP_NAME \
	--template-file $TEMPLATE \
	--parameters $PARAMETERS \
	--output none

if [[ $? == 0 ]]; then
	echo "[$TEMPLATE] Bicep template successfully validated"
else
	echo "Failed to validate the [$TEMPLATE] Bicep template"
	exit 1
fi

# Deploy the Bicep template
echo "Deploying the [$TEMPLATE] Bicep template..."
DEPLOYMENT_OUTPUTS=$(az deployment group create \
	--name $DEPLOYMENT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--template-file $TEMPLATE \
	--parameters $PARAMETERS \
	--query properties.outputs)

if [[ $? == 0 ]]; then
	echo "[$TEMPLATE] Bicep template successfully deployed"
else
	echo "Failed to deploy the [$TEMPLATE] Bicep template"
	exit 1
fi

WEB_APP_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r .webAppName.value)
FUNCTION_APP_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r .functionAppName.value)
WEB_APP_HOSTNAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r .webAppHostName.value)

if [[ -z "$WEB_APP_NAME" || -z "$FUNCTION_APP_NAME" ]]; then
	echo "Web App Name or Function App Name is empty. Exiting."
	exit 1
fi

# Create the zip package of the web app
cd "$CURRENT_DIR/../src" || exit
if [ -f "$WEBAPP_ZIPFILE" ]; then
	rm "$WEBAPP_ZIPFILE"
fi
echo "Creating zip package of the web app..."
zip -r "$WEBAPP_ZIPFILE" app.py gunicorn.conf.py requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$WEBAPP_ZIPFILE]..."
az webapp deploy \
	--resource-group $RESOURCE_GROUP_NAME \
	--name "$WEB_APP_NAME" \
	--src-path "$WEBAPP_ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [[ $? == 0 ]]; then
	echo "Web app [$WEB_APP_NAME] deployed successfully"
else
	echo "Failed to deploy web app [$WEB_APP_NAME]"
	exit 1
fi
rm -f "$WEBAPP_ZIPFILE"

# Create the zip package of the function app
cd "$CURRENT_DIR/../function" || exit
if [ -f "$WORKER_ZIPFILE" ]; then
	rm "$WORKER_ZIPFILE"
fi
echo "Creating zip package of the function app..."
zip -r "$WORKER_ZIPFILE" function_app.py host.json requirements.txt

# Deploy the function app
echo "Deploying function app [$FUNCTION_APP_NAME] with zip file [$WORKER_ZIPFILE]..."
az functionapp deploy \
	--resource-group $RESOURCE_GROUP_NAME \
	--name "$FUNCTION_APP_NAME" \
	--src-path "$WORKER_ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [[ $? == 0 ]]; then
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully"
else
	echo "Failed to deploy function app [$FUNCTION_APP_NAME]"
	exit 1
fi
rm -f "$WORKER_ZIPFILE"

echo "Deployment completed. Web app available at: http://$WEB_APP_HOSTNAME"
