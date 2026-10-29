#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
FUNCTION_APP_NAME="${PREFIX}-func-${SUFFIX}"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"

# Check resource group
az group show \
  --name $RESOURCE_GROUP_NAME \
  --output table

# List resources
az resource list \
  --resource-group $RESOURCE_GROUP_NAME \
  --output table

# Check function app status
az functionapp show  \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --output table

# Check storage account properties
az storage account show \
  --name $STORAGE_ACCOUNT_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --output table

# List storage containers
az storage container list \
  --account-name $STORAGE_ACCOUNT_NAME \
  --output table \
  --only-show-errors

# List storage queues
az storage queue list \
  --account-name $STORAGE_ACCOUNT_NAME \
  --output table \
  --only-show-errors

# List storage tables
az storage table list \
  --account-name $STORAGE_ACCOUNT_NAME \
  --output table \
  --only-show-errors