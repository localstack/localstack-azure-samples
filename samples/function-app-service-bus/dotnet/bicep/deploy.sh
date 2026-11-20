#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOCATION="westeurope"
VALIDATE_TEMPLATE=1
USE_WHAT_IF=0
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="functionapp.zip"
DEPLOY_RETRY_COUNT=3
DEPLOY_RETRY_SLEEP=30

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
		exit 1
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
			--only-show-errors

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			exit 1
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
			--only-show-errors)

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			echo "$output"
			exit 1
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
	--query 'properties.outputs' -o json); then
	# Extract only the JSON portion (everything from first { to the end)
	DEPLOYMENT_JSON=$(echo "$DEPLOYMENT_OUTPUTS" | sed -n '/{/,$ p')
	echo "Bicep template [$TEMPLATE] deployed successfully. Outputs:"
	echo "$DEPLOYMENT_JSON" | jq .
	FUNCTION_APP_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.functionAppName.value')
	SERVICE_BUS_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.serviceBusName.value')
	echo "Deployment details:"
	echo "Function App Name: $FUNCTION_APP_NAME"
	echo "Service Bus Namespace: $SERVICE_BUS_NAME"
else
	echo "Failed to deploy Bicep template [$TEMPLATE]"
	exit 1
fi

if [[ -z "$FUNCTION_APP_NAME" || -z "$SERVICE_BUS_NAME" ]]; then
	echo "Function App Name or Service Bus Namespace is empty. Exiting."
	exit 1
fi

# Print the names of the application settings of the function app, never their values, which hold secrets
echo "Retrieving the names of the application settings of the function app [$FUNCTION_APP_NAME]..."
az functionapp config appsettings list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--query "[].name" \
	--output tsv

# CD into the function app directory
cd ../src || exit

# Remove any existing zip package of the function app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Build and publish the function app
echo "Building function app [$FUNCTION_APP_NAME]..."
if dotnet publish -c Release -o ./publish; then
	echo "Function app [$FUNCTION_APP_NAME] built successfully."
else
	echo "Failed to build function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Create the zip package of the publish output
echo "Creating zip package of the function app..."
cd ./publish || exit
zip -r "../$ZIPFILE" .
cd ..

# Get the tier of the hosting plan of the function app and the host name of its deployment site. The Azure CLI shows
# them under properties since version 2.93.0, and at the top level before it
FUNCTION_APP_SKU=$(az functionapp show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--query "properties.sku || sku" \
	--output tsv)

if [[ $? != 0 || -z "$FUNCTION_APP_SKU" ]]; then
	echo "Failed to retrieve the hosting plan of function app [$FUNCTION_APP_NAME]."
	exit 1
fi

SCM_HOST_NAME=$(az functionapp show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--query "(properties.hostNameSslStates || hostNameSslStates)[?hostType=='Repository'] | [0].name" \
	--output tsv)

if [[ $? != 0 || -z "$SCM_HOST_NAME" ]]; then
	echo "Failed to retrieve the host name of the deployment site of function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Deploy the function app
echo "Deploying function app [$FUNCTION_APP_NAME] on the [$FUNCTION_APP_SKU] plan with zip file [$ZIPFILE]..."
# On Azure the first deployment to a new function app can time out (504) while its deployment site starts, so a failed
# attempt is retried
DEPLOYED=0
for ((ATTEMPT = 1; ATTEMPT <= DEPLOY_RETRY_COUNT; ATTEMPT++)); do
	az functionapp deployment source config-zip \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$FUNCTION_APP_NAME" \
		--src "$ZIPFILE" 1>/dev/null

	if [[ $? == 0 ]]; then
		DEPLOYED=1
		break
	fi

	# On the Flex Consumption plan, config-zip ends with a health check that accepts the default host name of the app
	# only without a port. LocalStack's carries one, so there the check fails after the deployment succeeded: the status
	# of the deployment itself decides (4 is success)
	if [[ "$FUNCTION_APP_SKU" == "FlexConsumption" ]]; then
		DEPLOYMENT_STATUS=$(az rest \
			--method get \
			--url "https://$SCM_HOST_NAME/api/deployments/latest" \
			--resource "$(az cloud show --query endpoints.appServiceResourceId --output tsv)" \
			--query status \
			--output tsv \
			--only-show-errors)

		if [[ "$DEPLOYMENT_STATUS" == "4" ]]; then
			echo "The deployment to function app [$FUNCTION_APP_NAME] succeeded; only the health check that ends config-zip failed."
			DEPLOYED=1
			break
		fi
	fi

	if [[ $ATTEMPT -lt $DEPLOY_RETRY_COUNT ]]; then
		echo "Attempt $ATTEMPT of $DEPLOY_RETRY_COUNT to deploy function app [$FUNCTION_APP_NAME] failed. Waiting [$DEPLOY_RETRY_SLEEP] seconds before retry..."
		sleep $DEPLOY_RETRY_SLEEP
	fi
done

if [[ $DEPLOYED == 1 ]]; then
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully."
else
	echo "Failed to deploy function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Remove the zip package of the function app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Print the list of resources in the resource group
echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table 