#!/bin/bash
set -euo pipefail

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-custom-image-rg"
ACR_NAME="${PREFIX}customimageacr"
APP_SERVICE_PLAN_NAME="${PREFIX}-custom-image-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="B1"
WEB_APP_NAME="${PREFIX}-custom-image-webapp-${SUFFIX}"
IMAGE_NAME="custom-image-webapp"
IMAGE_TAG="v1"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$CURRENT_DIR" || exit

echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
az group create \
	--name "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION"

echo "Creating Azure Container Registry [$ACR_NAME]..."
az acr create \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--sku Basic \
	--admin-enabled true

az acr login --name $ACR_NAME

LOGIN_SERVER=$(az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "loginServer" \
	--output tsv \
	--only-show-errors)

FULL_IMAGE="${LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"
LOCAL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building custom Docker image [$LOCAL_IMAGE]..."
docker build -t "$LOCAL_IMAGE" ../src/
docker tag "$LOCAL_IMAGE" "$FULL_IMAGE"

echo "Pushing image [$FULL_IMAGE] to ACR..."
docker push "$FULL_IMAGE"
WEBAPP_IMAGE="$FULL_IMAGE"


echo "Creating Linux App Service Plan [$APP_SERVICE_PLAN_NAME]..."
az appservice plan create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_SERVICE_PLAN_NAME" \
	--location "$LOCATION" \
	--sku "$APP_SERVICE_PLAN_SKU" \
	--is-linux

echo "Creating Web App [$WEB_APP_NAME] from custom image [$WEBAPP_IMAGE]..."

az webapp create \
  --resource-group "$RESOURCE_GROUP_NAME" \
	--plan "$APP_SERVICE_PLAN_NAME" \
	--name "$WEB_APP_NAME" \
	--container-image-name "$WEBAPP_IMAGE"

echo "Setting Web App container settings..."
az webapp config appsettings set \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--settings \
		WEBSITE_PORT="80" \
		WEBSITES_PORT="80" \
		APP_NAME="Custom Image" \
		IMAGE_NAME="$WEBAPP_IMAGE"

echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table

echo ""
echo "Deployment complete."
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "App Service Plan: $APP_SERVICE_PLAN_NAME"
echo "Web App: $WEB_APP_NAME"
echo "ACR: $ACR_NAME ($LOGIN_SERVER)"
echo "Image: $WEBAPP_IMAGE"
echo ""
echo "Run 'bash scripts/validate.sh' to verify the deployment."
