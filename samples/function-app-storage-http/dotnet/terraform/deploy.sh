#!/bin/bash

# Variables
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Start azure CLI local mode session
azlocal start_interception

# Run terraform init and apply
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using tflocal for LocalStack emulator environment."
	TERRAFORM_CMD="tflocal"
else
	echo "Using standard terraform for AzureCloud environment."
	TERRAFORM_CMD="terraform"
fi

# Run terraform init and apply
echo "Initializing Terraform..."
$TERRAFORM_CMD init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
$TERRAFORM_CMD plan -out=tfplan

if [[ $? != 0 ]]; then
		echo "Terraform plan failed. Exiting."
		exit 1
fi

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
tflocal apply -auto-approve tfplan

# Get the output values
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
FUNCTION_APP_NAME=$(terraform output -raw function_app_name)

# Print the variables
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Function App: $FUNCTION_APP_NAME"

# CD into the function app directory
cd ../src/sample || exit

# Clean and build the project in Release configuration
dotnet clean
dotnet build -c Release

# Publish the project to a publish directory
dotnet publish -c Release -o publish

# Create deployment zip from the published output
cd publish || exit
zip -r ../azure-function-deployment.zip .
cd .. || exit

# Deploy the function app using the zip file
echo "Deploying function app [$FUNCTION_APP_NAME]..."
azlocal functionapp deploy \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$FUNCTION_APP_NAME" \
    --src-path ./azure-function-deployment.zip \
    --type zip

# Stop azure CLI local mode session
azlocal stop_interception
