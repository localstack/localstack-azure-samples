#!/bin/bash

# Variables
# Check resource group
az group show \
  --name local-rg \
  --output table

# List resources
az resource list \
  --resource-group local-rg \
  --output table

# Check function app status
az functionapp show  \
  --name local-func-test \
  --resource-group local-rg \
  --output table

# Check storage account properties
az storage account show \
  --name localstoragetest \
  --resource-group local-rg \
  --output table

# List storage containers
az storage container list \
  --account-name localstoragetest \
  --output table \
  --only-show-errors

# List storage queues
az storage queue list \
  --account-name localstoragetest \
  --output table \
  --only-show-errors

# List storage tables
az storage table list \
  --account-name localstoragetest \
  --output table \
  --only-show-errors