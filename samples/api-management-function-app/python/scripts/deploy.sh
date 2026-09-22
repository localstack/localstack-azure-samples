#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}invstorage${SUFFIX}"
APP_SERVICE_PLAN_NAME="${PREFIX}-inventory-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU='B1'
FUNCTION_APP_NAME="${PREFIX}-inventory-functionapp-${SUFFIX}"
RUNTIME='python'
RUNTIME_VERSION='3.11'
FUNCTIONS_VERSION='4'
APIM_NAME="${PREFIX}-inventory-apim-${SUFFIX}"
APIM_SKU='Consumption'
APIM_PUBLISHER_NAME='LocalStack'
APIM_PUBLISHER_EMAIL='noreply@localstack.cloud'
APIM_API_VERSION='2022-08-01'
API_ID='inventory-api'
API_DISPLAY_NAME='Inventory API'
API_PATH='inventory'
PRODUCT_ID='inventory-partners'
PRODUCT_NAME='Inventory Partners'
APIM_SUBSCRIPTION_ID='partner-subscription'
NAMED_VALUE_ID='backend-secret'
FUNCTION_ZIPFILE='inventory_function.zip'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
APIM_DIR="$CURRENT_DIR/../apim"

# Get the current subscription
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

# The emulator's Function App answers on plain HTTP under its own hostname, while real Azure
# serves *.azurewebsites.net over HTTPS. Everything else below is the same on both.
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	BACKEND_SCHEME='http'
else
	BACKEND_SCHEME='https'
fi

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

# Check if the storage account already exists
echo "Checking if [$STORAGE_ACCOUNT_NAME] storage account actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$STORAGE_ACCOUNT_NAME] storage account actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$STORAGE_ACCOUNT_NAME] storage account in the [$RESOURCE_GROUP_NAME] resource group..."

	az storage account create \
		--name $STORAGE_ACCOUNT_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--sku Standard_LRS 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$STORAGE_ACCOUNT_NAME] storage account successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$STORAGE_ACCOUNT_NAME] storage account in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$STORAGE_ACCOUNT_NAME] storage account already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the app service plan already exists
echo "Checking if [$APP_SERVICE_PLAN_NAME] app service plan actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az appservice plan show --name $APP_SERVICE_PLAN_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APP_SERVICE_PLAN_NAME] app service plan actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$APP_SERVICE_PLAN_NAME] app service plan in the [$RESOURCE_GROUP_NAME] resource group..."

	az appservice plan create \
		--name $APP_SERVICE_PLAN_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--sku $APP_SERVICE_PLAN_SKU \
		--is-linux 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$APP_SERVICE_PLAN_NAME] app service plan successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$APP_SERVICE_PLAN_NAME] app service plan in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$APP_SERVICE_PLAN_NAME] app service plan already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the function app already exists
echo "Checking if [$FUNCTION_APP_NAME] function app actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az functionapp show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$FUNCTION_APP_NAME] function app actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$FUNCTION_APP_NAME] function app in the [$RESOURCE_GROUP_NAME] resource group..."

	az functionapp create \
		--name $FUNCTION_APP_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--plan $APP_SERVICE_PLAN_NAME \
		--storage-account $STORAGE_ACCOUNT_NAME \
		--runtime $RUNTIME \
		--runtime-version $RUNTIME_VERSION \
		--functions-version $FUNCTIONS_VERSION \
		--os-type Linux 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$FUNCTION_APP_NAME] function app successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$FUNCTION_APP_NAME] function app in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$FUNCTION_APP_NAME] function app already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the API Management service already exists
echo "Checking if [$APIM_NAME] API Management service actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APIM_NAME] API Management service actually exists in the [$RESOURCE_GROUP_NAME] resource group"

	# A deleted instance is soft-deleted and keeps its name reserved until it is purged, so an
	# earlier run's instance would make the create below fail with a conflict. Purge it first.
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

	echo "Creating [$APIM_NAME] API Management service in the [$RESOURCE_GROUP_NAME] resource group..."

	# The Consumption tier provisions in minutes on Azure; the classic tiers take the better
	# part of an hour.
	az apim create \
		--name $APIM_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--sku-name $APIM_SKU \
		--publisher-name "$APIM_PUBLISHER_NAME" \
		--publisher-email "$APIM_PUBLISHER_EMAIL" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$APIM_NAME] API Management service successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$APIM_NAME] API Management service in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$APIM_NAME] API Management service already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

APIM_ID=$(az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)

# The shared secret the gateway adds to every backend call lives in a secret named value, so the
# policy document refers to it as {{backend-secret}} and never contains it. A re-run reuses the
# stored value, which keeps the gateway and the Function App in agreement.
echo "Checking if [$NAMED_VALUE_ID] named value actually exists in the [$APIM_NAME] API Management service..."
az apim nv show --named-value-id $NAMED_VALUE_ID --service-name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$NAMED_VALUE_ID] named value actually exists in the [$APIM_NAME] API Management service"
	echo "Creating [$NAMED_VALUE_ID] named value in the [$APIM_NAME] API Management service..."
	BACKEND_SECRET=$(openssl rand -hex 16)

	az apim nv create \
		--named-value-id $NAMED_VALUE_ID \
		--display-name $NAMED_VALUE_ID \
		--service-name $APIM_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--secret true \
		--value "$BACKEND_SECRET" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$NAMED_VALUE_ID] named value successfully created in the [$APIM_NAME] API Management service"
	else
		echo "Failed to create [$NAMED_VALUE_ID] named value in the [$APIM_NAME] API Management service"
		exit 1
	fi
else
	echo "[$NAMED_VALUE_ID] named value already exists in the [$APIM_NAME] API Management service"
	BACKEND_SECRET=$(az apim nv show-secret \
		--named-value-id $NAMED_VALUE_ID \
		--service-name $APIM_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--query value \
		--output tsv)

	if [[ -z "$BACKEND_SECRET" ]]; then
		echo "Failed to read the [$NAMED_VALUE_ID] named value from the [$APIM_NAME] API Management service"
		exit 1
	fi
fi

# Configure the function app settings: the same secret the gateway injects
echo "Setting app settings for the [$FUNCTION_APP_NAME] function app..."
az functionapp config appsettings set \
	--name $FUNCTION_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	FUNCTIONS_WORKER_RUNTIME="$RUNTIME" \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	BACKEND_SECRET="$BACKEND_SECRET" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "App settings for the [$FUNCTION_APP_NAME] function app successfully set"
else
	echo "Failed to set app settings for the [$FUNCTION_APP_NAME] function app"
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
	--name $FUNCTION_APP_NAME \
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

# The backend address of the API: the Function App's hostname plus the Functions route prefix
FUNCTION_APP_HOSTNAME=$(az functionapp show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query defaultHostName --output tsv)
BACKEND_URL="$BACKEND_SCHEME://$FUNCTION_APP_HOSTNAME/api"
echo "Backend URL = $BACKEND_URL"

# Check if the API already exists
echo "Checking if [$API_ID] API actually exists in the [$APIM_NAME] API Management service..."
az apim api show --api-id $API_ID --service-name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$API_ID] API actually exists in the [$APIM_NAME] API Management service"
	echo "Importing [$API_ID] API from [openapi.json] into the [$APIM_NAME] API Management service..."

	# The operations come from the OpenAPI document; the backend address is given here because
	# it is only known once the Function App exists.
	az apim api import \
		--api-id $API_ID \
		--display-name "$API_DISPLAY_NAME" \
		--path $API_PATH \
		--service-name $APIM_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--specification-format OpenApiJson \
		--specification-path "$APIM_DIR/openapi.json" \
		--service-url "$BACKEND_URL" \
		--subscription-required true 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$API_ID] API successfully imported into the [$APIM_NAME] API Management service"
	else
		echo "Failed to import [$API_ID] API into the [$APIM_NAME] API Management service"
		exit 1
	fi
else
	echo "[$API_ID] API already exists in the [$APIM_NAME] API Management service"
fi

# Apply the API policy. Policies are validated when they are saved, so a mistake in the document
# is reported here rather than at the first request. The body is built with jq so the XML needs
# no escaping by hand. Updating an existing API Management entity needs an If-Match header, and
# * accepts whatever ETag the entity currently has.
echo "Applying the API policy to the [$API_ID] API..."
POLICY_URL="$APIM_ID/apis/$API_ID/policies/policy?api-version=$APIM_API_VERSION"
# rawxml, matching bicep/main.bicep: the shared document is uploaded verbatim, so a policy
# expression containing &&, < or & needs no XML escaping and cannot break this variant alone.
POLICY_BODY=$(jq -n --rawfile xml "$APIM_DIR/inventory-api-policy.xml" '{properties: {format: "rawxml", value: $xml}}')
az rest --method get --url "$POLICY_URL" &>/dev/null

if [[ $? == 0 ]]; then
	az rest --method put --url "$POLICY_URL" --headers "If-Match=*" --body "$POLICY_BODY" --output none
else
	az rest --method put --url "$POLICY_URL" --body "$POLICY_BODY" --output none
fi

if [[ $? == 0 ]]; then
	echo "API policy successfully applied to the [$API_ID] API"
else
	echo "Failed to apply the API policy to the [$API_ID] API"
	exit 1
fi

# Check if the product already exists
echo "Checking if [$PRODUCT_ID] product actually exists in the [$APIM_NAME] API Management service..."
az apim product show --product-id $PRODUCT_ID --service-name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$PRODUCT_ID] product actually exists in the [$APIM_NAME] API Management service"
	echo "Creating [$PRODUCT_ID] product in the [$APIM_NAME] API Management service..."

	az apim product create \
		--product-id $PRODUCT_ID \
		--product-name "$PRODUCT_NAME" \
		--description "Partners reading stock levels through the Inventory API" \
		--service-name $APIM_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--subscription-required true \
		--approval-required false \
		--state published 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$PRODUCT_ID] product successfully created in the [$APIM_NAME] API Management service"
	else
		echo "Failed to create [$PRODUCT_ID] product in the [$APIM_NAME] API Management service"
		exit 1
	fi
else
	echo "[$PRODUCT_ID] product already exists in the [$APIM_NAME] API Management service"
fi

# Add the API to the product (a PUT, so re-runs are harmless)
echo "Adding the [$API_ID] API to the [$PRODUCT_ID] product..."
az apim product api add \
	--product-id $PRODUCT_ID \
	--api-id $API_ID \
	--service-name $APIM_NAME \
	--resource-group $RESOURCE_GROUP_NAME 1>/dev/null

if [[ $? == 0 ]]; then
	echo "[$API_ID] API successfully added to the [$PRODUCT_ID] product"
else
	echo "Failed to add the [$API_ID] API to the [$PRODUCT_ID] product"
	exit 1
fi

# Check if the subscription already exists. The az CLI has no subscription commands, so this goes
# through az rest. The scope is the product: the key opens every API the product contains, and
# nothing else.
echo "Checking if [$APIM_SUBSCRIPTION_ID] subscription actually exists in the [$APIM_NAME] API Management service..."
SUBSCRIPTION_URL="$APIM_ID/subscriptions/$APIM_SUBSCRIPTION_ID?api-version=$APIM_API_VERSION"
az rest --method get --url "$SUBSCRIPTION_URL" &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APIM_SUBSCRIPTION_ID] subscription actually exists in the [$APIM_NAME] API Management service"
	echo "Creating [$APIM_SUBSCRIPTION_ID] subscription in the [$APIM_NAME] API Management service..."
	PRODUCT_RESOURCE_ID=$(az apim product show --product-id $PRODUCT_ID --service-name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)
	SUBSCRIPTION_BODY=$(jq -n --arg scope "$PRODUCT_RESOURCE_ID" '{properties: {displayName: "Partner subscription", scope: $scope, state: "active"}}')

	az rest --method put --url "$SUBSCRIPTION_URL" --body "$SUBSCRIPTION_BODY" --output none

	if [[ $? == 0 ]]; then
		echo "[$APIM_SUBSCRIPTION_ID] subscription successfully created in the [$APIM_NAME] API Management service"
	else
		echo "Failed to create [$APIM_SUBSCRIPTION_ID] subscription in the [$APIM_NAME] API Management service"
		exit 1
	fi
else
	echo "[$APIM_SUBSCRIPTION_ID] subscription already exists in the [$APIM_NAME] API Management service"
fi

# Where the gateway answers. The emulator also reports Azure's *.azure-api.net address in
# gatewayUrl, but that name only resolves once LocalStack's DNS is in front of the machine, so
# the local alias is printed instead.
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	GATEWAY_URL="http://${APIM_NAME}.apim.azure.localhost.localstack.cloud:4566"
else
	GATEWAY_URL=$(az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME --query gatewayUrl --output tsv)
fi

echo "Deployment completed. The Inventory API is available at: $GATEWAY_URL/$API_PATH"
echo "Read the subscription key with:"
echo "  az rest --method post --url \"$APIM_ID/subscriptions/$APIM_SUBSCRIPTION_ID/listSecrets?api-version=$APIM_API_VERSION\" --query primaryKey --output tsv"
echo "Then call the API with:"
echo "  curl -H \"Ocp-Apim-Subscription-Key: <key>\" \"$GATEWAY_URL/$API_PATH/items\""
