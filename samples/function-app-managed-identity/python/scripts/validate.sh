#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
INPUT_STORAGE_CONTAINER_NAME='input'
OUTPUT_STORAGE_CONTAINER_NAME='output'
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
FUNCTION_APP_NAME="${PREFIX}-functionapp-${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-insights-${SUFFIX}"

# Check resource group
echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
az group show \
	--name "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Azure Function App
echo -e "\n[$FUNCTION_APP_NAME] function app:\n"
az functionapp show \
	--name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,State:state,Location:location,DefaultHostName:defaultHostName}' \
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

# Check the diagnostic settings of the function app and of its App Service plan
FUNCTION_APP_ID=$(az functionapp show \
	--name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
APP_SERVICE_PLAN_ID=$(az functionapp show \
	--name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query appServicePlanId \
	--output tsv \
	--only-show-errors)

echo -e "\n[$FUNCTION_APP_NAME] function app diagnostic settings:\n"
az monitor diagnostic-settings list \
	--resource "$FUNCTION_APP_ID" \
	--query "[].{Name:name,Logs:join(', ', logs[?enabled].category),Metrics:join(', ', metrics[?enabled].category)}" \
	--output table \
	--only-show-errors

echo -e "\nApp Service plan diagnostic settings:\n"
az monitor diagnostic-settings list \
	--resource "$APP_SERVICE_PLAN_ID" \
	--query "[].{Name:name,Metrics:join(', ', metrics[?enabled].category)}" \
	--output table \
	--only-show-errors

# Check the diagnostic settings of the storage account, of its blob, queue and table services, and of the Log Analytics
# workspace
STORAGE_ACCOUNT_ID=$(az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

echo -e "\n[$STORAGE_ACCOUNT_NAME] storage account diagnostic settings:\n"
az monitor diagnostic-settings list \
	--resource "$STORAGE_ACCOUNT_ID" \
	--query "[].{Name:name,Metrics:join(', ', metrics[?enabled].category)}" \
	--output table \
	--only-show-errors

for SERVICE in blob queue table; do
	echo -e "\n[$STORAGE_ACCOUNT_NAME] $SERVICE service diagnostic settings:\n"
	az monitor diagnostic-settings list \
		--resource "$STORAGE_ACCOUNT_ID/${SERVICE}Services/default" \
		--query "[].{Name:name,Logs:join(', ', logs[?enabled].category),Metrics:join(', ', metrics[?enabled].category)}" \
		--output table \
		--only-show-errors
done

echo -e "\n[$LOG_ANALYTICS_NAME] Log Analytics workspace diagnostic settings:\n"
az monitor diagnostic-settings list \
	--resource "$LOG_ANALYTICS_ID" \
	--query "[].{Name:name,Logs:join(', ', logs[?enabled].category),Metrics:join(', ', metrics[?enabled].category)}" \
	--output table \
	--only-show-errors

# List resources
echo -e "\n[$RESOURCE_GROUP_NAME] all resources:\n"
az resource list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors
