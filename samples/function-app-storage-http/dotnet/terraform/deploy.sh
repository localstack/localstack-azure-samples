#!/bin/bash

# Variables
PREFIX='funchttp' #system or user
SUFFIX='test'
LOCATION='westeurope'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="function_app.zip"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Run terraform init and apply
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	AZ="azlocal"
else
	echo "Using standard terraform and az for AzureCloud environment."
	AZ="az"
fi

echo "Initializing Terraform..."
terraform init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION"

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
zip -r ../$ZIPFILE .
cd .. || exit

# Deploy the function app using the zip file
echo "Deploying function app [$FUNCTION_APP_NAME]..."
if $AZ functionapp deploy \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$FUNCTION_APP_NAME" \
    --src-path $ZIPFILE \
    --type zip 1> /dev/null; then
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully."
else
	echo "Warning: Failed to deploy function app [$FUNCTION_APP_NAME]."
fi
