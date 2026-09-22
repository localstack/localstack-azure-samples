#!/bin/bash

# Variables
# Overridable so the same scripts can deploy to real Azure, where the API Management service, the
# storage account and the Function App all need globally unique names:
#   PREFIX=apimdemo SUFFIX=$RANDOM bash deploy.sh
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
APIM_NAME="${PREFIX}-inventory-apim-${SUFFIX}"
APIM_API_VERSION='2022-08-01'
FUNCTION_ZIPFILE='inventory_function.zip'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# The emulator serves the Function App over plain HTTP under its own hostname; real Azure serves
# *.azurewebsites.net over HTTPS. Picked here the way scripts/deploy.sh picks it, so neither
# deployment needs the file edited.
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	BACKEND_SCHEME='http'
	# What points the azurerm provider at the emulator instead of the real Azure endpoints.
	export ARM_METADATA_HOSTNAME='localhost.localstack.cloud:4566'
	export ARM_SUBSCRIPTION_ID='00000000-0000-0000-0000-000000000000'
else
	BACKEND_SCHEME='https'
	export ARM_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
fi

# A deleted API Management instance is soft-deleted and keeps its name reserved until it is
# purged, so an earlier run's instance (the scripts variant's, say) would make Terraform's create
# fail with a conflict. Purge it first, unless the instance is live and is simply being updated.
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

# Initialize Terraform
echo "Initializing Terraform..."
terraform init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "backend_scheme=$BACKEND_SCHEME"

if [[ $? != 0 ]]; then
	echo "Terraform plan failed. Exiting."
	exit 1
fi

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
terraform apply -auto-approve tfplan

if [[ $? != 0 ]]; then
	echo "Terraform apply failed. Exiting."
	exit 1
fi

# Get the output values
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
FUNCTION_APP_NAME=$(terraform output -raw function_app_name)
APIM_NAME=$(terraform output -raw apim_name)
API_PATH=$(terraform output -raw api_path)
APIM_SUBSCRIPTION_ID=$(terraform output -raw subscription_id)

# Check if output values are empty
if [[ -z "$FUNCTION_APP_NAME" || -z "$APIM_NAME" ]]; then
	echo "Function App Name or API Management Name is empty. Exiting."
	exit 1
fi

# Change current directory to the function folder
cd "$CURRENT_DIR/../function" || exit

# Remove any existing zip package of the function app
if [ -f "$FUNCTION_ZIPFILE" ]; then
	rm "$FUNCTION_ZIPFILE"
fi

# Create the zip package of the function app
echo "Creating zip package of the function app..."
zip -r "$FUNCTION_ZIPFILE" function_app.py host.json requirements.txt

# Deploy the function app
echo "Deploying function app [$FUNCTION_APP_NAME] with zip file [$FUNCTION_ZIPFILE]..."
az functionapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--src-path "$FUNCTION_ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully."
else
	echo "Failed to deploy function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Remove the zip package of the function app
if [ -f "$FUNCTION_ZIPFILE" ]; then
	rm "$FUNCTION_ZIPFILE"
fi

# Where the gateway answers. The emulator also reports Azure's *.azure-api.net address in
# gatewayUrl, but that name only resolves once LocalStack's DNS is in front of the machine, so
# the local alias is printed instead.
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	GATEWAY_URL="http://${APIM_NAME}.apim.azure.localhost.localstack.cloud:4566"
else
	GATEWAY_URL=$(cd "$CURRENT_DIR" && terraform output -raw gateway_url)
fi
APIM_ID=$(az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv)

echo "Deployment completed. The Inventory API is available at: $GATEWAY_URL/$API_PATH"
echo "Read the subscription key with:"
echo "  az rest --method post --url \"$APIM_ID/subscriptions/$APIM_SUBSCRIPTION_ID/listSecrets?api-version=$APIM_API_VERSION\" --query primaryKey --output tsv"
echo "Then call the API with:"
echo "  curl -H \"Ocp-Apim-Subscription-Key: <key>\" \"$GATEWAY_URL/$API_PATH/items\""
