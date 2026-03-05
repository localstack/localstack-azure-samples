#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
SERVICEBUS_QUEUE_NAME="myqueue" # Queue name is hardcoded in the application properties
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"
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

# Intialize Terraform
echo "Initializing Terraform..."
terraform init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
        -var "prefix=$PREFIX" \
        -var "suffix=$SUFFIX" \
        -var "location=$LOCATION" \
				-var "queue_name=$SERVICEBUS_QUEUE_NAME"

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
SERVICEBUS_NAMESPACE_NAME=$(terraform output -raw namespace_name)


if [[ -z "$SERVICEBUS_NAMESPACE_NAME" ]]; then
	echo "Service Bus Namespace Name is empty. Exiting."
	exit 1
fi

# Retrieve the connection string for the Service Bus namespace
echo "Retrieving connection string for [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace..."
AZURE_SERVICEBUS_CONNECTION_STRING=$($AZ servicebus namespace authorization-rule keys list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--namespace-name "$SERVICEBUS_NAMESPACE_NAME" \
	--name RootManageSharedAccessKey \
	--query primaryConnectionString \
	--output tsv)

if [[ $? -eq 0 ]] && [[ -n "$AZURE_SERVICEBUS_CONNECTION_STRING" ]]; then
	export AZURE_SERVICEBUS_CONNECTION_STRING
	echo "Connection string retrieved successfully."
else
	echo "Failed to retrieve connection string."
	exit 1
fi

# Start the Java application
echo "Starting Java application..."
cd "$CURRENT_DIR/../app" && mvn clean spring-boot:run

# Optionally tear down all resources (uncomment to enable)
# echo "Deleting resource group [$RESOURCE_GROUP_NAME]..."
# $AZ group delete --name "$RESOURCE_GROUP_NAME" --yes
