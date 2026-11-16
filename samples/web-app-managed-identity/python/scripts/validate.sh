#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
CONTAINER_NAME='activities'
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-insights-${SUFFIX}"

# Check resource group
echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
az group show \
	--name "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check App Service Plan
echo -e "\n[$APP_SERVICE_PLAN_NAME] app service plan:\n"
az appservice plan show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_SERVICE_PLAN_NAME" \
	--output table \
	--only-show-errors

# Check Azure Web App
echo -e "\n[$WEB_APP_NAME] web app:\n"
az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,State:state,Location:location,DefaultHostName:defaultHostName}' \
	--output table \
	--only-show-errors

# Check user-assigned managed identity
echo -e "\n[$MANAGED_IDENTITY_NAME] managed identity:\n"
az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,ClientId:clientId,PrincipalId:principalId}' \
	--output table \
	--only-show-errors

# Check storage account
echo -e "\n[$STORAGE_ACCOUNT_NAME] storage account:\n"
az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,Kind:kind,Sku:sku.name}' \
	--output table \
	--only-show-errors

# List storage containers
echo -e "\n[$STORAGE_ACCOUNT_NAME] storage containers:\n"
az storage container list \
	--account-name "$STORAGE_ACCOUNT_NAME" \
	--output table \
	--only-show-errors

# Check Log Analytics workspace
echo -e "\n[$LOG_ANALYTICS_NAME] Log Analytics workspace:\n"
az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,Sku:sku.name,RetentionInDays:retentionInDays}' \
	--output table \
	--only-show-errors

# Check Application Insights component
echo -e "\n[$APPLICATION_INSIGHTS_NAME] Application Insights component:\n"
az monitor app-insights component show \
	--app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,ApplicationType:applicationType,WorkspaceResourceId:workspaceResourceId}' \
	--output table \
	--only-show-errors

# Check the diagnostic settings of the web app and of its App Service plan
WEB_APP_ID=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
APP_SERVICE_PLAN_ID=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query appServicePlanId \
	--output tsv \
	--only-show-errors)

echo -e "\n[$WEB_APP_NAME] web app diagnostic settings:\n"
az monitor diagnostic-settings list \
	--resource "$WEB_APP_ID" \
	--query "[].{Name:name,Logs:join(', ', logs[?enabled].category),Metrics:join(', ', metrics[?enabled].category)}" \
	--output table \
	--only-show-errors

echo -e "\nApp Service plan diagnostic settings:\n"
az monitor diagnostic-settings list \
	--resource "$APP_SERVICE_PLAN_ID" \
	--query "[].{Name:name,Metrics:join(', ', metrics[?enabled].category)}" \
	--output table \
	--only-show-errors

# List resources
echo -e "\n[$RESOURCE_GROUP_NAME] all resources:\n"
az resource list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors
