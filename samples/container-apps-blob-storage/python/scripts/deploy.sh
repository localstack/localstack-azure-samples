#!/bin/bash

# =============================================================================
# Container Apps Guestbook - Deployment Script
#
# Deploys the Guestbook app using three Azure services:
#   1. Azure Blob Storage    - Stores guestbook entries as a JSON blob
#   2. Azure Container Registry (ACR) - Hosts the Docker container image
#   3. Azure Container Apps  - Runs the containerized Flask app behind the
#                              managed environment's HTTP ingress
#
# The storage connection string is stored as a Container Apps secret and
# injected into the container through a secretref environment variable.
# =============================================================================

# Variables
PREFIX='local'
LOCATION='eastus'
RESOURCE_GROUP_NAME="${PREFIX}-aca-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}acastorage"
BLOB_CONTAINER_NAME="guestbook"
ACR_NAME="${PREFIX}acaacr"
ACA_ENV_NAME="${PREFIX}-aca-env"
ACA_APP_NAME="${PREFIX}-aca-guestbook"
IMAGE_NAME="guestbook"
IMAGE_TAG="v1"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit
# =============================================================================
# Step 1: Create Resource Group
# =============================================================================
echo ""
echo "============================================================"
echo "Step 1: Creating resource group [$RESOURCE_GROUP_NAME]..."
echo "============================================================"
az group create \
	--name $RESOURCE_GROUP_NAME \
	--location $LOCATION \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Resource group [$RESOURCE_GROUP_NAME] created successfully."
else
	echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
	exit 1
fi

# =============================================================================
# Step 2: Create Storage Account
# =============================================================================
echo ""
echo "============================================================"
echo "Step 2: Creating storage account [$STORAGE_ACCOUNT_NAME]..."
echo "============================================================"
az storage account create \
	--name $STORAGE_ACCOUNT_NAME \
	--location $LOCATION \
	--resource-group $RESOURCE_GROUP_NAME \
	--sku Standard_LRS \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Storage account [$STORAGE_ACCOUNT_NAME] created successfully."
else
	echo "Failed to create storage account [$STORAGE_ACCOUNT_NAME]."
	exit 1
fi

# =============================================================================
# Step 3: Get Storage Account Key
# =============================================================================
echo ""
echo "============================================================"
echo "Step 3: Retrieving storage account key..."
echo "============================================================"
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
	--account-name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "[0].value" \
	--output tsv)

if [ -n "$STORAGE_ACCOUNT_KEY" ]; then
	echo "Storage account key retrieved successfully."
else
	echo "Failed to retrieve storage account key."
	exit 1
fi

# =============================================================================
# Step 4: Get Storage Blob Endpoint
# =============================================================================
echo ""
echo "============================================================"
echo "Step 4: Retrieving storage blob endpoint..."
echo "============================================================"
BLOB_ENDPOINT=$(az storage account show \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "primaryEndpoints.blob" \
	--output tsv \
	--only-show-errors)

if [ -n "$BLOB_ENDPOINT" ]; then
	echo "Blob endpoint: $BLOB_ENDPOINT"
else
	echo "Failed to retrieve blob endpoint."
	exit 1
fi

# Build the connection string using the original blob endpoint (resolvable from the host).
STORAGE_CONN_STRING="DefaultEndpointsProtocol=http;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_ACCOUNT_KEY};BlobEndpoint=${BLOB_ENDPOINT}"
echo "Connection string built successfully."

# For LocalStack, the Container Apps runtime configures the cluster with LocalStack's
# DNS server, so *.localhost.localstack.cloud resolves to the LocalStack container.
# We only need to downgrade HTTPS to HTTP (containers don't have the LS TLS cert).
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	CONTAINER_BLOB_ENDPOINT="${BLOB_ENDPOINT/https:\/\//http:\/\/}"
	CONTAINER_CONN_STRING="DefaultEndpointsProtocol=http;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_ACCOUNT_KEY};BlobEndpoint=${CONTAINER_BLOB_ENDPOINT}"
	echo "Container blob endpoint: $CONTAINER_BLOB_ENDPOINT"
else
	CONTAINER_CONN_STRING="$STORAGE_CONN_STRING"
fi

# =============================================================================
# Step 5: Create Blob Container
# =============================================================================
echo ""
echo "============================================================"
echo "Step 5: Creating blob container [$BLOB_CONTAINER_NAME]..."
echo "============================================================"
# Use --connection-string to ensure the correct endpoint is used
# (--account-name constructs its own hostname which may not match LocalStack's cert)
az storage container create \
	--name $BLOB_CONTAINER_NAME \
	--connection-string "$STORAGE_CONN_STRING" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Blob container [$BLOB_CONTAINER_NAME] created successfully."
else
	echo "Failed to create blob container [$BLOB_CONTAINER_NAME]."
	exit 1
fi

# =============================================================================
# Step 6: Create Azure Container Registry (ACR)
# =============================================================================
echo ""
echo "============================================================"
echo "Step 6: Creating ACR [$ACR_NAME] with admin user enabled..."
echo "============================================================"
az acr create \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--sku Basic \
	--admin-enabled true \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "ACR [$ACR_NAME] created successfully."
else
	echo "Failed to create ACR [$ACR_NAME]."
	exit 1
fi

# =============================================================================
# Step 7: Get ACR Login Server and Credentials
# =============================================================================
echo ""
echo "============================================================"
echo "Step 7: Retrieving ACR credentials..."
echo "============================================================"
LOGIN_SERVER=$(az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "loginServer" \
	--output tsv \
	--only-show-errors)

if [ -z "$LOGIN_SERVER" ]; then
	echo "Failed to retrieve ACR login server."
	exit 1
fi
echo "ACR Login Server: $LOGIN_SERVER"

ACR_USERNAME=$(az acr credential show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "username" \
	--output tsv \
	--only-show-errors)

ACR_PASSWORD=$(az acr credential show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "passwords[0].value" \
	--output tsv \
	--only-show-errors)

if [ -n "$ACR_USERNAME" ] && [ -n "$ACR_PASSWORD" ]; then
	echo "ACR credentials retrieved successfully. Username: $ACR_USERNAME"
else
	echo "Failed to retrieve ACR credentials."
	exit 1
fi

# =============================================================================
# Step 8: Build and Push Docker Image to ACR
# =============================================================================
echo ""
echo "============================================================"
echo "Step 8: Building and pushing Docker image to ACR..."
echo "============================================================"

FULL_IMAGE="${LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

# Build the Docker image
echo "Building Docker image [$IMAGE_NAME:$IMAGE_TAG]..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" ../src/

if [ $? -eq 0 ]; then
	echo "Docker image built successfully."
else
	echo "Failed to build Docker image."
	exit 1
fi

# Tag for ACR
docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "$FULL_IMAGE"

# Login to ACR
echo "Logging in to ACR [$LOGIN_SERVER]..."
echo "$ACR_PASSWORD" | docker login "$LOGIN_SERVER" --username "$ACR_USERNAME" --password-stdin 2>/dev/null

if [ $? -eq 0 ]; then
	echo "Logged in to ACR successfully."
else
	echo "Warning: Failed to login to ACR. Will attempt push anyway."
fi

# Push to ACR
echo "Pushing image [$FULL_IMAGE]..."
docker push "$FULL_IMAGE" 2>/dev/null

if [ $? -eq 0 ]; then
	echo "Image pushed to ACR successfully."
else
	echo "Failed to push image to ACR."
	exit 1
fi

# =============================================================================
# Step 9: Create Container Apps Managed Environment
# =============================================================================
echo ""
echo "============================================================"
echo "Step 9: Creating Container Apps environment [$ACA_ENV_NAME]..."
echo "============================================================"
# --logs-destination none keeps the CLI from provisioning a Log Analytics
# workspace, which this sample does not use.
az containerapp env create \
	--name "$ACA_ENV_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--logs-destination none \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Container Apps environment [$ACA_ENV_NAME] created successfully."
else
	echo "Failed to create Container Apps environment [$ACA_ENV_NAME]."
	exit 1
fi

# =============================================================================
# Step 10: Create Container App
# =============================================================================
echo ""
echo "============================================================"
echo "Step 10: Creating container app [$ACA_APP_NAME]..."
echo "============================================================"
# The registry credentials are passed explicitly: the CLI only infers them from
# ARM when the server ends in ".azurecr.io", and LocalStack's loginServer is its
# own host. The storage connection string becomes the Container Apps secret
# [storage-conn], referenced from the container via a secretref env var.
az containerapp create \
	--name "$ACA_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--environment "$ACA_ENV_NAME" \
	--image "$FULL_IMAGE" \
	--container-name "$IMAGE_NAME" \
	--registry-server "$LOGIN_SERVER" \
	--registry-username "$ACR_USERNAME" \
	--registry-password "$ACR_PASSWORD" \
	--secrets storage-conn="$CONTAINER_CONN_STRING" \
	--env-vars \
		AZURE_STORAGE_CONNECTION_STRING=secretref:storage-conn \
		BLOB_CONTAINER_NAME="$BLOB_CONTAINER_NAME" \
		APP_REVISION="$IMAGE_TAG" \
	--ingress external \
	--target-port 8080 \
	--transport http \
	--allow-insecure \
	--revisions-mode multiple \
	--revision-suffix "$IMAGE_TAG" \
	--cpu 0.5 --memory 1Gi \
	--min-replicas 1 --max-replicas 3 \
	--scale-rule-name http-scale \
	--scale-rule-type http \
	--scale-rule-http-concurrency 50 \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Container app [$ACA_APP_NAME] created successfully."
else
	echo "Failed to create container app [$ACA_APP_NAME]."
	exit 1
fi

FQDN=$(az containerapp show \
	--name "$ACA_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "properties.configuration.ingress.fqdn" \
	--output tsv \
	--only-show-errors)

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================================"
echo "Deployment Complete!"
echo "============================================================"
echo "Resource Group:    $RESOURCE_GROUP_NAME"
echo "Storage Account:   $STORAGE_ACCOUNT_NAME"
echo "Blob Container:    $BLOB_CONTAINER_NAME"
echo "ACR:               $ACR_NAME ($LOGIN_SERVER)"
echo "ACA Environment:   $ACA_ENV_NAME"
echo "Container App:     $ACA_APP_NAME"
echo "Image:             $FULL_IMAGE"
echo "Ingress FQDN:      $FQDN"
if [[ "$FQDN" == *"localhost.localstack.cloud"* ]]; then
	echo "App URL:           http://${FQDN}:4566/"
else
	echo "App URL:           https://${FQDN}/"
fi
echo ""
echo "Run 'bash scripts/validate.sh' to verify the deployment."
echo "============================================================"
