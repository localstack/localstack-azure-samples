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
# By default the storage connection string is stored as a Container Apps
# secret and injected into the container through a secretref environment
# variable. Set MANAGED_IDENTITY_TYPE to SystemAssigned or UserAssigned to have
# the app reach Blob Storage with a managed identity instead, granted the
# Storage Blob Data Contributor role on the storage account.
# =============================================================================

# Variables
PREFIX="${PREFIX:-local}"
LOCATION='eastus'
RESOURCE_GROUP_NAME="${PREFIX}-aca-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}acastorage"
BLOB_CONTAINER_NAME="guestbook"
ACR_NAME="${PREFIX}acaacr"
ACA_ENV_NAME="${PREFIX}-aca-env"
ACA_APP_NAME="${PREFIX}-aca-guestbook"
IMAGE_NAME="guestbook"
IMAGE_TAG="v1"
MANAGED_IDENTITY_TYPE="${MANAGED_IDENTITY_TYPE:-None}"
MANAGED_IDENTITY_NAME="${PREFIX}-aca-identity"
STORAGE_ROLE="Storage Blob Data Contributor"
# A role is assigned to a managed identity right after the identity is created: the retries cover the time the new
# principal takes to replicate to Microsoft Entra ID
ROLE_ASSIGNMENT_RETRY_COUNT=5
ROLE_ASSIGNMENT_RETRY_SLEEP=10
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "$MANAGED_IDENTITY_TYPE" in
None | SystemAssigned | UserAssigned) ;;
*)
	echo "MANAGED_IDENTITY_TYPE must be None, SystemAssigned or UserAssigned, not [$MANAGED_IDENTITY_TYPE]."
	exit 1
	;;
esac

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Assign a role to a principal at a scope, unless the assignment already exists. The assignee is given as an
# object id together with its principal type, so no directory lookup happens at creation time.
# $1: the object id of the principal
# $2: the principal type (ServicePrincipal, User or Group)
# $3: the role name
# $4: the scope (resource id)
# $5: the description of the principal, used in messages
# $6: the description of the scope, used in messages
ensure_role_assignment() {
	local principal_id=$1
	local principal_type=$2
	local role=$3
	local scope=$4
	local principal_description=$5
	local scope_description=$6
	local current attempt

	echo "Checking if the $principal_description has the [$role] role assignment on the $scope_description..."
	current=$(az role assignment list \
		--assignee "$principal_id" \
		--scope "$scope" \
		--query "[?roleDefinitionName=='$role'].roleDefinitionName" \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ $current == "$role" ]]; then
		echo "The $principal_description already has the [$role] role assignment on the $scope_description"
		return 0
	fi

	echo "Assigning the [$role] role to the $principal_description on the $scope_description..."
	for attempt in $(seq 1 "$ROLE_ASSIGNMENT_RETRY_COUNT"); do
		if az role assignment create \
			--assignee-object-id "$principal_id" \
			--assignee-principal-type "$principal_type" \
			--role "$role" \
			--scope "$scope" \
			--only-show-errors 1>/dev/null; then
			echo "[$role] role successfully assigned to the $principal_description on the $scope_description"
			return 0
		fi

		if [ "$attempt" -lt "$ROLE_ASSIGNMENT_RETRY_COUNT" ]; then
			echo "Attempt $attempt of $ROLE_ASSIGNMENT_RETRY_COUNT to assign the [$role] role failed; retrying in $ROLE_ASSIGNMENT_RETRY_SLEEP seconds..."
			sleep "$ROLE_ASSIGNMENT_RETRY_SLEEP"
		fi
	done

	echo "Failed to assign the [$role] role to the $principal_description on the $scope_description"
	exit 1
}

# =============================================================================
# Step 1: Create Resource Group
# =============================================================================
echo ""
echo "============================================================"
echo "Step 1: Creating resource group [$RESOURCE_GROUP_NAME]..."
echo "============================================================"
if az group show --name "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists."
else
	az group create \
		--name "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] created successfully."
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
		exit 1
	fi
fi

# =============================================================================
# Step 2: Create Storage Account
# =============================================================================
echo ""
echo "============================================================"
echo "Step 2: Creating storage account [$STORAGE_ACCOUNT_NAME]..."
echo "============================================================"
if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	echo "Storage account [$STORAGE_ACCOUNT_NAME] already exists."
else
	az storage account create \
		--name "$STORAGE_ACCOUNT_NAME" \
		--location "$LOCATION" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--sku Standard_LRS \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Storage account [$STORAGE_ACCOUNT_NAME] created successfully."
	else
		echo "Failed to create storage account [$STORAGE_ACCOUNT_NAME]."
		exit 1
	fi
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
CONTAINER_EXISTS=$(az storage container exists \
	--name "$BLOB_CONTAINER_NAME" \
	--connection-string "$STORAGE_CONN_STRING" \
	--query exists \
	--output tsv \
	--only-show-errors 2>/dev/null | tr -d '\r')

if [[ $CONTAINER_EXISTS == "true" ]]; then
	echo "Blob container [$BLOB_CONTAINER_NAME] already exists."
else
	az storage container create \
		--name "$BLOB_CONTAINER_NAME" \
		--connection-string "$STORAGE_CONN_STRING" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Blob container [$BLOB_CONTAINER_NAME] created successfully."
	else
		echo "Failed to create blob container [$BLOB_CONTAINER_NAME]."
		exit 1
	fi
fi

# =============================================================================
# Step 5b: Create the User-Assigned Managed Identity (UserAssigned only)
# =============================================================================
STORAGE_ACCOUNT_ID=$(az storage account show \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "id" \
	--output tsv \
	--only-show-errors)

if [[ $MANAGED_IDENTITY_TYPE == "UserAssigned" ]]; then
	echo ""
	echo "============================================================"
	echo "Step 5b: Creating managed identity [$MANAGED_IDENTITY_NAME]..."
	echo "============================================================"
	if az identity show --name "$MANAGED_IDENTITY_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
		echo "Managed identity [$MANAGED_IDENTITY_NAME] already exists."
	elif az identity create \
		--name "$MANAGED_IDENTITY_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null; then
		echo "Managed identity [$MANAGED_IDENTITY_NAME] created successfully."
	else
		echo "Failed to create managed identity [$MANAGED_IDENTITY_NAME]."
		exit 1
	fi

	# tr turns the three lines into one, and drops the carriage return the Azure CLI ends each line with on Windows
	read -r IDENTITY_ID IDENTITY_CLIENT_ID IDENTITY_PRINCIPAL_ID < <(az identity show \
		--name "$MANAGED_IDENTITY_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query "[id, clientId, principalId]" \
		--output tsv \
		--only-show-errors | tr -d '\r' | tr '\n' ' ')

	if [ -n "$IDENTITY_PRINCIPAL_ID" ]; then
		echo "Managed identity [$MANAGED_IDENTITY_NAME] Client ID: $IDENTITY_CLIENT_ID"
	else
		echo "Failed to retrieve managed identity [$MANAGED_IDENTITY_NAME]."
		exit 1
	fi

	ensure_role_assignment "$IDENTITY_PRINCIPAL_ID" "ServicePrincipal" "$STORAGE_ROLE" "$STORAGE_ACCOUNT_ID" "[$MANAGED_IDENTITY_NAME] managed identity" "[$STORAGE_ACCOUNT_NAME] storage account"
fi

# =============================================================================
# Step 6: Create Azure Container Registry (ACR)
# =============================================================================
echo ""
echo "============================================================"
echo "Step 6: Creating ACR [$ACR_NAME] with admin user enabled..."
echo "============================================================"
if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	echo "ACR [$ACR_NAME] already exists."
else
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
if az containerapp env show --name "$ACA_ENV_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	echo "Container Apps environment [$ACA_ENV_NAME] already exists."
else
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
# own host. Without a managed identity the storage connection string becomes
# the Container Apps secret [storage-conn], referenced from the container via a
# secretref env var; with one, the app gets the blob endpoint (HTTPS, as a
# token credential requires) instead of the storage secret.
case "$MANAGED_IDENTITY_TYPE" in
None)
	STORAGE_ARGS=(--secrets storage-conn="$STORAGE_CONN_STRING")
	STORAGE_ENV_VARS=(AZURE_STORAGE_CONNECTION_STRING=secretref:storage-conn)
	;;
SystemAssigned)
	STORAGE_ARGS=(--system-assigned)
	STORAGE_ENV_VARS=(AZURE_STORAGE_ACCOUNT_URL="$BLOB_ENDPOINT")
	;;
UserAssigned)
	STORAGE_ARGS=(--user-assigned "$IDENTITY_ID")
	STORAGE_ENV_VARS=(AZURE_STORAGE_ACCOUNT_URL="$BLOB_ENDPOINT" AZURE_CLIENT_ID="$IDENTITY_CLIENT_ID")
	;;
esac

if az containerapp show --name "$ACA_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	# The app keeps its revision: the revision suffix is the image tag, so a new revision needs a new IMAGE_TAG
	echo "Container app [$ACA_APP_NAME] already exists."
else
	az containerapp create \
		--name "$ACA_APP_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--environment "$ACA_ENV_NAME" \
		--image "$FULL_IMAGE" \
		--container-name "$IMAGE_NAME" \
		--registry-server "$LOGIN_SERVER" \
		--registry-username "$ACR_USERNAME" \
		--registry-password "$ACR_PASSWORD" \
		"${STORAGE_ARGS[@]}" \
		--env-vars \
			"${STORAGE_ENV_VARS[@]}" \
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
fi

# A system-assigned identity only exists once the app does, so it is granted
# access afterwards. Until the role propagates, Blob Storage rejects the app's
# requests; validate.sh retries the round trip for that reason.
if [[ $MANAGED_IDENTITY_TYPE == "SystemAssigned" ]]; then
	APP_PRINCIPAL_ID=$(az containerapp show \
		--name "$ACA_APP_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query "identity.principalId" \
		--output tsv \
		--only-show-errors)

	if [ -z "$APP_PRINCIPAL_ID" ]; then
		echo "Container app [$ACA_APP_NAME] has no system-assigned identity."
		exit 1
	fi
	echo "System-assigned identity principal ID: $APP_PRINCIPAL_ID"
	ensure_role_assignment "$APP_PRINCIPAL_ID" "ServicePrincipal" "$STORAGE_ROLE" "$STORAGE_ACCOUNT_ID" "system-assigned identity of the [$ACA_APP_NAME] container app" "[$STORAGE_ACCOUNT_NAME] storage account"
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
echo "Managed Identity:  $MANAGED_IDENTITY_TYPE"
echo "Ingress FQDN:      $FQDN"
if [[ "$FQDN" == *"localhost.localstack.cloud" ]]; then
	echo "App URL:           http://${FQDN}:4566/"
else
	echo "App URL:           https://${FQDN}/"
fi
echo ""
echo "Run 'bash scripts/validate.sh' to verify the deployment."
echo "============================================================"
