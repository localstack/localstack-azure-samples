#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="functionapp.zip"

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

# Print the application settings of the function app
echo "Retrieving application settings for function app [$FUNCTION_APP_NAME]..."
az functionapp config appsettings list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME"

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

# Deploy the function app
echo "Deploying function app [$FUNCTION_APP_NAME] with zip file [$ZIPFILE]..."
if az functionapp deployment source config-zip \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--src "$ZIPFILE" 1>/dev/null; then
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
