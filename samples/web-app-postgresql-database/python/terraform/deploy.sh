#!/bin/bash

# Variables
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	AZ="azlocal"
else
	echo "Using standard az for AzureCloud environment."
	AZ="az"
fi

echo "Initializing Terraform..."
terraform init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
terraform apply -auto-approve tfplan

if [[ $? != 0 ]]; then
	echo "Terraform apply failed. Exiting."
	exit 1
fi

# Get the output values
echo ""
echo "=== Terraform Outputs ==="
terraform output

RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
SERVER_NAME=$(terraform output -raw server_name)
SERVER_FQDN=$(terraform output -raw server_fqdn)
DATABASE_NAME=$(terraform output -raw database_name)

echo ""
echo "=== Deployment Complete ==="
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Server Name:    $SERVER_NAME"
echo "Server FQDN:    $SERVER_FQDN"
echo "Database:       $DATABASE_NAME"
