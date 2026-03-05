#!/bin/bash

# =============================================================================
# ACI Vacation Planner - Deployment Script
#
# Deploys the Vacation Planner app using four Azure services:
#   1. Azure Blob Storage   - Stores vacation activities as JSON blobs
#   2. Azure Key Vault      - Stores the storage connection string as a secret
#   3. Azure Container Registry (ACR) - Hosts the Docker container image
#   4. Azure Container Instances (ACI) - Runs the containerized Flask app
# =============================================================================

# Variables
PREFIX='local'
LOCATION='eastus'
RESOURCE_GROUP_NAME="${PREFIX}-aci-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}acistorage"
BLOB_CONTAINER_NAME="activities"
KEY_VAULT_NAME="${PREFIX}acikv"
ACR_NAME="${PREFIX}aciacr"
ACI_GROUP_NAME="${PREFIX}-aci-planner"
IMAGE_NAME="vacation-planner"
IMAGE_TAG="v1"
LOGIN_NAME="paolo"
ENVIRONMENT=$(az account show --query environmentName --output tsv)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Choose the appropriate CLI based on the environment
# When start_interception is active, 'az' already routes to LocalStack,
# so we use 'az' directly to avoid double-wrapping.
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using az with LocalStack interception active."
	AZ="az"
else
	echo "Using standard az for AzureCloud environment."
	AZ="az"
fi

# =============================================================================
# Step 1: Create Resource Group
# =============================================================================
echo ""
echo "============================================================"
echo "Step 1: Creating resource group [$RESOURCE_GROUP_NAME]..."
echo "============================================================"
$AZ group create \
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
$AZ storage account create \
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
STORAGE_ACCOUNT_KEY=$($AZ storage account keys list \
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
BLOB_ENDPOINT=$($AZ storage account show \
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

# For LocalStack, convert https:// to http:// to avoid SSL certificate issues
# with self-signed certs on data-plane endpoints
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	BLOB_ENDPOINT="${BLOB_ENDPOINT/https:\/\//http:\/\/}"
	echo "Converted blob endpoint to HTTP: $BLOB_ENDPOINT"
fi

# Build connection string
STORAGE_CONN_STRING="DefaultEndpointsProtocol=http;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_ACCOUNT_KEY};BlobEndpoint=${BLOB_ENDPOINT}"
echo "Connection string built successfully."

# =============================================================================
# Step 5: Create Blob Container
# =============================================================================
echo ""
echo "============================================================"
echo "Step 5: Creating blob container [$BLOB_CONTAINER_NAME]..."
echo "============================================================"
# Use --connection-string to ensure the correct endpoint is used
# (--account-name constructs its own hostname which may not match LocalStack's cert)
$AZ storage container create \
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
# Step 6: Create Key Vault
# =============================================================================
echo ""
echo "============================================================"
echo "Step 6: Creating Key Vault [$KEY_VAULT_NAME]..."
echo "============================================================"
$AZ keyvault create \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--enable-rbac-authorization true \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Key Vault [$KEY_VAULT_NAME] created successfully."
else
	echo "Failed to create Key Vault [$KEY_VAULT_NAME]."
	exit 1
fi

# =============================================================================
# Step 7: Store Storage Connection String in Key Vault
# =============================================================================
echo ""
echo "============================================================"
echo "Step 7: Storing storage connection string in Key Vault..."
echo "============================================================"
$AZ keyvault secret set \
	--vault-name "$KEY_VAULT_NAME" \
	--name "storage-conn" \
	--value "$STORAGE_CONN_STRING" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Secret [storage-conn] stored in Key Vault [$KEY_VAULT_NAME] successfully."
else
	echo "Failed to store secret in Key Vault."
	exit 1
fi

# Retrieve secret to verify and pass to ACI
RETRIEVED_CONN_STRING=$($AZ keyvault secret show \
	--vault-name "$KEY_VAULT_NAME" \
	--name "storage-conn" \
	--query "value" \
	--output tsv \
	--only-show-errors)

if [ -n "$RETRIEVED_CONN_STRING" ]; then
	echo "Secret retrieved from Key Vault successfully."
else
	echo "Failed to retrieve secret from Key Vault."
	exit 1
fi

# =============================================================================
# Step 8: Create Azure Container Registry (ACR)
# =============================================================================
echo ""
echo "============================================================"
echo "Step 8: Creating ACR [$ACR_NAME] with admin user enabled..."
echo "============================================================"
$AZ acr create \
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
# Step 9: Get ACR Login Server and Credentials
# =============================================================================
echo ""
echo "============================================================"
echo "Step 9: Retrieving ACR credentials..."
echo "============================================================"
LOGIN_SERVER=$($AZ acr show \
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

ACR_USERNAME=$($AZ acr credential show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "username" \
	--output tsv \
	--only-show-errors)

ACR_PASSWORD=$($AZ acr credential show \
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
# Step 10: Build and Push Docker Image to ACR
# =============================================================================
echo ""
echo "============================================================"
echo "Step 10: Building and pushing Docker image to ACR..."
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
	USE_ACR_IMAGE=true
else
	echo "Warning: Failed to push image to ACR. Falling back to local image."
	FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
	USE_ACR_IMAGE=false
fi

# =============================================================================
# Step 11: Create ACI Container Group
# =============================================================================
echo ""
echo "============================================================"
echo "Step 11: Creating ACI container group [$ACI_GROUP_NAME]..."
echo "============================================================"

if [ "$USE_ACR_IMAGE" = true ]; then
	$AZ container create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$ACI_GROUP_NAME" \
		--image "$FULL_IMAGE" \
		--registry-login-server "$LOGIN_SERVER" \
		--registry-username "$ACR_USERNAME" \
		--registry-password "$ACR_PASSWORD" \
		--environment-variables \
			AZURE_STORAGE_CONNECTION_STRING="$RETRIEVED_CONN_STRING" \
			BLOB_CONTAINER_NAME="$BLOB_CONTAINER_NAME" \
			LOGIN_NAME="$LOGIN_NAME" \
		--ip-address Public \
		--ports 80 \
		--cpu 1 --memory 1 \
		--os-type Linux \
		--restart-policy Always \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null
else
	$AZ container create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$ACI_GROUP_NAME" \
		--image "$FULL_IMAGE" \
		--environment-variables \
			AZURE_STORAGE_CONNECTION_STRING="$RETRIEVED_CONN_STRING" \
			BLOB_CONTAINER_NAME="$BLOB_CONTAINER_NAME" \
			LOGIN_NAME="$LOGIN_NAME" \
		--ip-address Public \
		--ports 80 \
		--cpu 1 --memory 1 \
		--os-type Linux \
		--restart-policy Always \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null
fi

if [ $? -eq 0 ]; then
	echo "ACI container group [$ACI_GROUP_NAME] created successfully."
else
	echo "Failed to create ACI container group [$ACI_GROUP_NAME]."
	exit 1
fi

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
echo "Key Vault:         $KEY_VAULT_NAME"
echo "ACR:               $ACR_NAME ($LOGIN_SERVER)"
echo "ACI Container:     $ACI_GROUP_NAME"
echo "Image:             $FULL_IMAGE"
echo ""
echo "Run 'bash scripts/validate.sh' to verify the deployment."
echo "============================================================"
