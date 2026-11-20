#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="functionapp.zip"
DEPLOY_RETRY_COUNT=3
DEPLOY_RETRY_SLEEP=30

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Intialize Terraform
echo "Initializing Terraform..."
terraform init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION"

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
SERVICE_BUS_NAMESPACE=$(terraform output -raw service_bus_namespace_name)

if [[ -z "$RESOURCE_GROUP_NAME" || -z "$FUNCTION_APP_NAME" || -z "$SERVICE_BUS_NAMESPACE" ]]; then
	echo "Resource Group Name, Function App Name, or Service Bus Namespace is empty. Exiting."
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
