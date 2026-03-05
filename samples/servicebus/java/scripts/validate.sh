#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
SERVICEBUS_NAMESPACE_NAME="${PREFIX}-sb-ns-${SUFFIX}"
SERVICEBUS_QUEUE_NAME="myqueue"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
  echo "Using azlocal for LocalStack emulator environment."
  AZ="azlocal"
else
  echo "Using standard az for AzureCloud environment."
  AZ="az"
fi

# Check resource group
echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
$AZ group show \
  --name "$RESOURCE_GROUP_NAME" \
  --output table \
  --only-show-errors

# Check Service Bus namespace
echo -e "\n[$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace:\n"
$AZ servicebus namespace show \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$SERVICEBUS_NAMESPACE_NAME" \
	--query "{name:name, location:location, serviceBusEndpoint:serviceBusEndpoint, status:provisioningState}" \
  --output table \
  --only-show-errors

# Check Service Bus queue
echo -e "\n[$SERVICEBUS_QUEUE_NAME] Service Bus queue:\n"
$AZ servicebus queue show \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --namespace-name "$SERVICEBUS_NAMESPACE_NAME" \
  --name "$SERVICEBUS_QUEUE_NAME" \
	--query "{name:name, messageCount:messageCount, sizeInBytes:sizeInBytes}" \
  --output table \
  --only-show-errors