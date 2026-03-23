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

# Check Azure Web App
az webapp show \
--name local-webapp-test \
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