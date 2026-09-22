#!/bin/bash

# Variables
# Overridable so the same scripts can deploy to real Azure, where the API Management service, the
# storage account and the Function App all need globally unique names:
#   PREFIX=apimdemo SUFFIX=$RANDOM bash deploy.sh
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
DEPLOYMENT_NAME='api-management-function-app'
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
APIM_API_VERSION='2022-08-01'
FUNCTION_ZIPFILE='inventory_function.zip'
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

# A deleted API Management instance is soft-deleted and keeps its name reserved until it is
# purged, so an earlier run's instance (the scripts variant's, say) would make the deployment
# fail with a conflict. Purge it first, unless the instance is live and is simply being updated.
APIM_NAME="${PREFIX}-inventory-apim-${SUFFIX}"
az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	az apim deletedservice show --service-name $APIM_NAME --location "$LOCATION" &>/dev/null

	if [[ $? == 0 ]]; then
		echo "Purging the soft-deleted [$APIM_NAME] API Management service that still holds the name..."
		az apim deletedservice purge --service-name $APIM_NAME --location "$LOCATION" 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "Soft-deleted [$APIM_NAME] API Management service successfully purged"
		else
			echo "Failed to purge the soft-deleted [$APIM_NAME] API Management service"
			exit 1
		fi
	fi
fi

# main.bicepparam reads all four of these from the environment. The scheme is picked the way
# scripts/deploy.sh picks it: the emulator serves the Function App over plain HTTP, real Azure over
# HTTPS, and the template derives the app's httpsOnly from the same value.
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	export BACKEND_SCHEME='http'
else
	export BACKEND_SCHEME='https'
fi
export PREFIX SUFFIX

# Generate the shared secret the gateway adds to every backend call; main.bicepparam reads it
# from the environment, and the template stores it both as the Function App's setting and as the
# secret named value the policy references.
export BACKEND_SECRET=$(openssl rand -hex 16)

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
az deployment group create \
	--name $DEPLOYMENT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--template-file $TEMPLATE \
	--parameters $PARAMETERS \
	--output none

if [[ $? == 0 ]]; then
	echo "[$TEMPLATE] Bicep template successfully deployed"
else
	echo "Failed to deploy the [$TEMPLATE] Bicep template"
	exit 1
fi

# Each output is read back on its own rather than parsed out of the create's stdout: the Azure CLI
# prefixes that stdout with lines such as "Bicep CLI is already installed at ...", which is not JSON,
# so piping it into jq fails and every name comes back empty. Seen on real Azure, not on the emulator.
deployment_output() {
	az deployment group show \
		--name $DEPLOYMENT_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--query "properties.outputs.$1.value" \
		--output tsv
}

FUNCTION_APP_NAME=$(deployment_output functionAppName)
APIM_NAME=$(deployment_output apimName)
API_PATH=$(deployment_output apiPath)
APIM_SUBSCRIPTION_ID=$(deployment_output subscriptionName)
GATEWAY_URL=$(deployment_output gatewayUrl)

if [[ -z "$FUNCTION_APP_NAME" || -z "$APIM_NAME" ]]; then
	echo "Function App Name or API Management Name is empty. Exiting."
	exit 1
fi

# Create the zip package of the function app
cd "$CURRENT_DIR/../function" || exit
if [ -f "$FUNCTION_ZIPFILE" ]; then
	rm "$FUNCTION_ZIPFILE"
fi
echo "Creating zip package of the function app..."
zip -r "$FUNCTION_ZIPFILE" function_app.py host.json requirements.txt

# Deploy the function app
echo "Deploying function app [$FUNCTION_APP_NAME] with zip file [$FUNCTION_ZIPFILE]..."
az functionapp deploy \
	--resource-group $RESOURCE_GROUP_NAME \
	--name "$FUNCTION_APP_NAME" \
	--src-path "$FUNCTION_ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [[ $? == 0 ]]; then
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully"
else
	echo "Failed to deploy function app [$FUNCTION_APP_NAME]"
	exit 1
fi
rm -f "$FUNCTION_ZIPFILE"

# Where the gateway answers. The emulator also reports Azure's *.azure-api.net address in
# gatewayUrl, but that name only resolves once LocalStack's DNS is in front of the machine, so
# the local alias is printed instead.
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	GATEWAY_URL="http://${APIM_NAME}.apim.azure.localhost.localstack.cloud:4566"
fi
APIM_ID=$(az apim show --name "$APIM_NAME" --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)

echo "Deployment completed. The Inventory API is available at: $GATEWAY_URL/$API_PATH"
echo "Read the subscription key with:"
echo "  az rest --method post --url \"$APIM_ID/subscriptions/$APIM_SUBSCRIPTION_ID/listSecrets?api-version=$APIM_API_VERSION\" --query primaryKey --output tsv"
echo "Then call the API with:"
echo "  curl -H \"Ocp-Apim-Subscription-Key: <key>\" \"$GATEWAY_URL/$API_PATH/items\""
