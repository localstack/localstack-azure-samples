#!/bin/bash

# Variables
RESOURCE_GROUP="rg-pgflex-bicep"
LOCATION='westeurope'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

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

# Create resource group
echo "Creating resource group [$RESOURCE_GROUP]..."
$AZ group create \
	--name "$RESOURCE_GROUP" \
	--location "$LOCATION" \
	--output table

if [[ $? != 0 ]]; then
	echo "Failed to create resource group. Exiting."
	exit 1
fi

# Deploy Bicep template
echo "Deploying Bicep template..."
$AZ deployment group create \
	--resource-group "$RESOURCE_GROUP" \
	--template-file main.bicep \
	--parameters main.bicepparam \
	--output table

if [[ $? != 0 ]]; then
	echo "Bicep deployment failed. Exiting."
	exit 1
fi

# Get deployment outputs
echo ""
echo "=== Deployment Outputs ==="
$AZ deployment group show \
	--resource-group "$RESOURCE_GROUP" \
	--name main \
	--query "properties.outputs" \
	--output json

echo ""
echo "Bicep deployment completed successfully."
