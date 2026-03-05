#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
SERVICEBUS_NAMESPACE_NAME="${PREFIX}-sb-ns-${SUFFIX}"
SERVICEBUS_QUEUE_NAME="myqueue" # Queue name is hardcoded in the application properties
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

# Check if the resource group already exists
echo "Checking for resource group [$RESOURCE_GROUP_NAME]..."
$AZ group show \
	--name "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "Resource group [$RESOURCE_GROUP_NAME] not found. Creating..."
	$AZ group create \
		--name "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? -eq 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] created successfully."
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
		exit 1
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists."
fi

# Check if the Service Bus namespace already exists
echo "Checking if [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace already exists in the [$RESOURCE_GROUP_NAME] resource group..."
$AZ servicebus namespace show \
	--name "$SERVICEBUS_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace found. Creating..."
	$AZ servicebus namespace create \
		--name "$SERVICEBUS_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? -eq 0 ]]; then
		echo "[$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace created successfully."
	else
		echo "Failed to create [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace."
		exit 1
	fi
else
	echo "[$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace already exists."
fi

# Check if the Service Bus queue already exists
echo "Checking if [$SERVICEBUS_QUEUE_NAME] queue already exists in the [$SERVICEBUS_NAMESPACE_NAME] namespace..."
$AZ servicebus queue show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--namespace-name "$SERVICEBUS_NAMESPACE_NAME" \
	--name "$SERVICEBUS_QUEUE_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$SERVICEBUS_QUEUE_NAME] queue found. Creating..."
	$AZ servicebus queue create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--namespace-name "$SERVICEBUS_NAMESPACE_NAME" \
		--name "$SERVICEBUS_QUEUE_NAME" \
		--only-show-errors 1>/dev/null

	if [[ $? -eq 0 ]]; then
		echo "[$SERVICEBUS_QUEUE_NAME] queue created successfully."
	else
		echo "Failed to create [$SERVICEBUS_QUEUE_NAME] queue."
		exit 1
	fi
else
	echo "[$SERVICEBUS_QUEUE_NAME] queue already exists."
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
