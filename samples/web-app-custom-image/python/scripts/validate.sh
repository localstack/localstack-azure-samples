#!/bin/bash
set -euo pipefail

PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-custom-image-rg"
ACR_NAME="${PREFIX}customimageacr"
APP_SERVICE_PLAN_NAME="${PREFIX}-custom-image-plan-${SUFFIX}"
WEB_APP_NAME="${PREFIX}-custom-image-webapp-${SUFFIX}"

echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
az group show \
	--name "$RESOURCE_GROUP_NAME" \
	--output table

echo -e "\n[$APP_SERVICE_PLAN_NAME] App Service Plan:\n"
az appservice plan show \
	--name "$APP_SERVICE_PLAN_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table

echo -e "\n[$ACR_NAME] Azure Container Registry:\n"
az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table

echo -e "\n[$WEB_APP_NAME] Web App:\n"
az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "{name:name, state:state, defaultHostName:defaultHostName, kind:kind}" \
	--output table

echo -e "\n[$WEB_APP_NAME] app settings:\n"
az webapp config appsettings list \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[?name=='IMAGE_NAME' || name=='WEBSITE_PORT' || name=='WEBSITES_PORT'].[name,value]" \
	--output table

echo -e "\nResources in [$RESOURCE_GROUP_NAME]:\n"
az resource list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table
