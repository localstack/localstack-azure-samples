#!/bin/bash

# Enable verbose debugging
set -x

# Variables
PREFIX='local'
SUFFIX='test'
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
RESOURCE_GROUP_NAME="$PREFIX-webapp-mi-rg"
LOCATION="westeurope"
VALIDATE_TEMPLATE=1
USE_WHAT_IF=0
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="webapp_app.zip"
MANAGED_IDENTITY_TYPE="UserAssigned" # SystemAssigned or UserAssigned
ENVIRONMENT=$(az account show --query environmentName --output tsv)

echo "=================================================="
echo "DEBUG: Starting bicep deployment for web-app-managed-identity"
echo "DEBUG: Resource Group: $RESOURCE_GROUP_NAME"
echo "DEBUG: Environment: $ENVIRONMENT"
echo "DEBUG: Managed Identity Type: $MANAGED_IDENTITY_TYPE"
echo "=================================================="

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

# Validates if the resource group exists in the subscription, if not creates it
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
$AZ group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	# Create the resource group
	$AZ group create \
		--name $RESOURCE_GROUP_NAME \
		--location $LOCATION \
		--only-show-errors 1>/dev/null

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
		$AZ deployment group what-if \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $TEMPLATE \
			--parameters $PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			managedIdentityType=$MANAGED_IDENTITY_TYPE \
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
		output=$($AZ deployment group validate \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $TEMPLATE \
			--parameters $PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			managedIdentityType=$MANAGED_IDENTITY_TYPE \
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
echo "DEBUG: Listing existing resource groups before deployment..."
$AZ group list --query "[].name" -o table || true

# Capture full deployment output for debugging
DEPLOYMENT_RESULT=$($AZ deployment group create \
	--resource-group $RESOURCE_GROUP_NAME \
	--template-file $TEMPLATE \
	--parameters $PARAMETERS \
	--parameters location=$LOCATION \
	prefix=$PREFIX \
	suffix=$SUFFIX \
	managedIdentityType=$MANAGED_IDENTITY_TYPE \
	-o json 2>&1) || true

echo "DEBUG: Full deployment result:"
echo "$DEPLOYMENT_RESULT" | jq . 2>/dev/null || echo "$DEPLOYMENT_RESULT"

# Check if deployment succeeded
PROVISIONING_STATE=$(echo "$DEPLOYMENT_RESULT" | jq -r '.properties.provisioningState // empty' 2>/dev/null)
echo "DEBUG: Provisioning State: $PROVISIONING_STATE"

if [[ "$PROVISIONING_STATE" == "Succeeded" ]]; then
	echo "Bicep template [$TEMPLATE] deployed successfully."

	# Extract outputs
	DEPLOYMENT_OUTPUTS=$(echo "$DEPLOYMENT_RESULT" | jq '.properties.outputs // empty' 2>/dev/null)

	if [[ -n "$DEPLOYMENT_OUTPUTS" ]] && echo "$DEPLOYMENT_OUTPUTS" | jq empty 2>/dev/null; then
		echo "Outputs:"
		echo "$DEPLOYMENT_OUTPUTS" | jq .
		APP_SERVICE_PLAN_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.appServicePlanName.value // empty')
		WEB_APP_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.webAppName.value // empty')
		WEB_APP_URL=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.webAppUrl.value // empty')
		STORAGE_ACCOUNT_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.storageAccountName.value // empty')
		echo "Deployment details:"
		echo "- appServicePlanName: $APP_SERVICE_PLAN_NAME"
		echo "- webAppName: $WEB_APP_NAME"
		echo "- webAppUrl: $WEB_APP_URL"
		echo "- storageAccountName: $STORAGE_ACCOUNT_NAME"
	else
		echo "Warning: Could not parse deployment outputs. Attempting to retrieve resource names directly..."

		WEB_APP_NAME=$($AZ webapp list \
			--resource-group $RESOURCE_GROUP_NAME \
			--query "[0].name" \
			-o tsv 2>/dev/null || echo "")

		STORAGE_ACCOUNT_NAME=$($AZ storage account list \
			--resource-group $RESOURCE_GROUP_NAME \
			--query "[0].name" \
			-o tsv 2>/dev/null || echo "")

		APP_SERVICE_PLAN_NAME=$($AZ appservice plan list \
			--resource-group $RESOURCE_GROUP_NAME \
			--query "[0].name" \
			-o tsv 2>/dev/null || echo "")

		echo "Retrieved resource names:"
		echo "- appServicePlanName: $APP_SERVICE_PLAN_NAME"
		echo "- webAppName: $WEB_APP_NAME"
		echo "- storageAccountName: $STORAGE_ACCOUNT_NAME"
	fi
else
	echo "ERROR: Bicep template [$TEMPLATE] deployment failed!"
	echo "Provisioning State: $PROVISIONING_STATE"
	echo ""
	echo "Full deployment error details:"
	echo "$DEPLOYMENT_RESULT" | jq . 2>/dev/null || echo "$DEPLOYMENT_RESULT"
	echo ""

	# Try to extract specific error message
	ERROR_MESSAGE=$(echo "$DEPLOYMENT_RESULT" | jq -r '.properties.error.message // .error.message // .message // empty' 2>/dev/null)
	ERROR_CODE=$(echo "$DEPLOYMENT_RESULT" | jq -r '.properties.error.code // .error.code // .code // empty' 2>/dev/null)
	if [[ -n "$ERROR_MESSAGE" ]]; then
		echo "Error Code: $ERROR_CODE"
		echo "Error Message: $ERROR_MESSAGE"
	fi

	# Check for resource-specific errors
	echo ""
	echo "DEBUG: Checking LocalStack logs..."
	docker logs localstack-main --tail 50 2>&1 | grep -i "error\|exception\|fail" || true

	exit 1
fi

# Validation before deploying the web app
if [[ -z "$WEB_APP_NAME" ]]; then
	echo "Web App Name is empty. Exiting."
	exit 1
fi

# CD into the web app directory
cd ../src || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py requirements.txt static templates

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
$AZ webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app [$WEB_APP_NAME] created successfully."
else
	echo "Failed to create web app [$WEB_APP_NAME]."
	exit 1
fi

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi
