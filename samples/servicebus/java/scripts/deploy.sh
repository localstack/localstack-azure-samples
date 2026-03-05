#!/bin/bash

# Variables
LOCATION='westeurope'
RESOURCE_GROUP_NAME="local-rg-$RANDOM"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICEBUS_NAMESPACE_NAME="ls-sb-ns-$RANDOM"
# Queue name is hardcoded in application properties
SERVICEBUS_QUEUE_NAME="myqueue"


# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Redirect AZ calls to LocalStack
azlocal start-interception

# Create a resource group
echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
az group create \
    --name $RESOURCE_GROUP_NAME \
    --location $LOCATION \
    --only-show-errors 1>/dev/null

# Create a ServiceBus Queue
az servicebus namespace create \
    --name $SERVICEBUS_NAMESPACE_NAME \
    --resource-group $RESOURCE_GROUP_NAME

queue_id=$(az servicebus queue create --resource-group $RESOURCE_GROUP_NAME --namespace-name $SERVICEBUS_NAMESPACE_NAME --name $SERVICEBUS_QUEUE_NAME --query 'id' --output tsv)

# Register connection string to use with our Application
export AZURE_SERVICEBUS_CONNECTION_STRING=$(az servicebus namespace authorization-rule keys list \
    --resource-group $RESOURCE_GROUP_NAME \
    --namespace-name $SERVICEBUS_NAMESPACE_NAME \
    --name RootManageSharedAccessKey \
    --query primaryConnectionString \
    --output tsv)

# START JAVA APP
cd ../app && mvn clean spring-boot:run

# Tear down all resources
az group delete \
    --name $RESOURCE_GROUP_NAME \
    --yes

azlocal stop-interception


