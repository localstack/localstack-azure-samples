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
PREFIX="${PREFIX:-local}"
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
SECRET_NAME="storage-conn"
KEY_VAULT_SECRETS_OFFICER_ROLE="Key Vault Secrets Officer"
ROLE_ASSIGNMENT_RETRY_COUNT=3
ROLE_ASSIGNMENT_RETRY_SLEEP=5
SECRET_RETRY_COUNT=20
SECRET_RETRY_SLEEP=30
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
	# The assignments are filtered on the principal id rather than with --assignee, which first looks the principal up in
	# Microsoft Graph: that lookup fails for a caller the directory doesn't list, such as the emulator's own caller
	current=$(az role assignment list \
		--scope "$scope" \
		--query "[?principalId=='$principal_id' && roleDefinitionName=='$role'].roleDefinitionName" \
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

# Store a secret in the key vault, unless it already holds the same value. The value is never printed.
# Reads and writes go through the Key Vault data plane, which the deploying principal can use only once its
# Key Vault Secrets Officer assignment has propagated, so the write is retried for a few minutes.
# $1: the secret name
# $2: the secret value
set_secret() {
	local secret_name=$1
	local secret_value=$2
	local current attempt

	echo "Checking if the [$secret_name] secret actually exists in the [$KEY_VAULT_NAME] key vault..."
	current=$(az keyvault secret show \
		--vault-name "$KEY_VAULT_NAME" \
		--name "$secret_name" \
		--query value \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ -n $current && $current == "$secret_value" ]]; then
		echo "The [$secret_name] secret already holds the expected value in the [$KEY_VAULT_NAME] key vault"
		return 0
	fi

	echo "Setting the [$secret_name] secret in the [$KEY_VAULT_NAME] key vault..."
	for attempt in $(seq 1 "$SECRET_RETRY_COUNT"); do
		if az keyvault secret set \
			--vault-name "$KEY_VAULT_NAME" \
			--name "$secret_name" \
			--value "$secret_value" \
			--only-show-errors 1>/dev/null; then
			echo "The [$secret_name] secret was successfully set in the [$KEY_VAULT_NAME] key vault"
			return 0
		fi

		if [ "$attempt" -lt "$SECRET_RETRY_COUNT" ]; then
			echo "Attempt $attempt of $SECRET_RETRY_COUNT to set the [$secret_name] secret failed (the [$KEY_VAULT_SECRETS_OFFICER_ROLE] assignment may still be propagating); retrying in $SECRET_RETRY_SLEEP seconds..."
			sleep "$SECRET_RETRY_SLEEP"
		fi
	done

	echo "Failed to set the [$secret_name] secret in the [$KEY_VAULT_NAME] key vault"
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
# Step 6: Create Key Vault
# =============================================================================
echo ""
echo "============================================================"
echo "Step 6: Creating Key Vault [$KEY_VAULT_NAME]..."
echo "============================================================"
# Recover the key vault if a previous run left it soft-deleted: deleting a key vault only soft-deletes it, and its
# name stays reserved for the retention period, so the create below would fail. Recovering restores the vault with
# its contents. The vault's own location is used: a soft-deleted vault stays in the region it was deleted in.
DELETED_KEY_VAULT_LOCATION=$(az keyvault list-deleted \
	--query "[?name=='$KEY_VAULT_NAME'].properties.location | [0]" \
	--output tsv \
	--only-show-errors 2>/dev/null | tr -d '\r')

if [[ -n $DELETED_KEY_VAULT_LOCATION ]]; then
	echo "Key Vault [$KEY_VAULT_NAME] exists in a soft-deleted state in [$DELETED_KEY_VAULT_LOCATION]: recovering it..."
	if az keyvault recover \
		--name "$KEY_VAULT_NAME" \
		--location "$DELETED_KEY_VAULT_LOCATION" \
		--only-show-errors 1>/dev/null; then
		echo "Key Vault [$KEY_VAULT_NAME] recovered successfully."
	else
		echo "Failed to recover the soft-deleted Key Vault [$KEY_VAULT_NAME]. Purge it and re-run this script:"
		echo "  az keyvault purge --name $KEY_VAULT_NAME --location $DELETED_KEY_VAULT_LOCATION"
		exit 1
	fi
fi

if az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	echo "Key Vault [$KEY_VAULT_NAME] already exists."
else
	az keyvault create \
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
fi

KEY_VAULT_ID=$(az keyvault show \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors | tr -d '\r')

if [[ -z $KEY_VAULT_ID ]]; then
	echo "Failed to retrieve the resource id of Key Vault [$KEY_VAULT_NAME]."
	exit 1
fi

# =============================================================================
# Step 7: Store Storage Connection String in Key Vault
# =============================================================================
echo ""
echo "============================================================"
echo "Step 7: Storing storage connection string in Key Vault..."
echo "============================================================"
# The vault uses the RBAC permission model, so writing and reading the secret needs the Key Vault Secrets Officer
# role on the vault: the script grants it to whoever runs it, a user or a service principal. The lookup goes through
# Microsoft Graph, then the oid claim of the CLI's own access token; when both fail, the role becomes a prerequisite.
ACCOUNT_USER_TYPE=$(az account show --query user.type --output tsv --only-show-errors)
ACCOUNT_USER_NAME=$(az account show --query user.name --output tsv --only-show-errors)

if [[ $ACCOUNT_USER_TYPE == "user" ]]; then
	DEPLOYER_PRINCIPAL_TYPE="User"
	DEPLOYER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv --only-show-errors 2>/dev/null)
else
	DEPLOYER_PRINCIPAL_TYPE="ServicePrincipal"
	DEPLOYER_OBJECT_ID=$(az ad sp show --id "$ACCOUNT_USER_NAME" --query id --output tsv --only-show-errors 2>/dev/null)
fi

if [[ -z $DEPLOYER_OBJECT_ID ]]; then
	DEPLOYER_OBJECT_ID=$(az account get-access-token --query accessToken --output tsv --only-show-errors 2>/dev/null |
		cut -d. -f2 | tr '_-' '/+' | awk '{ pad = length($0) % 4; if (pad == 2) $0 = $0 "=="; else if (pad == 3) $0 = $0 "="; print }' |
		base64 -d 2>/dev/null | jq -r '.oid // empty' 2>/dev/null)
fi

if [[ -n $DEPLOYER_OBJECT_ID ]]; then
	ensure_role_assignment "$DEPLOYER_OBJECT_ID" "$DEPLOYER_PRINCIPAL_TYPE" "$KEY_VAULT_SECRETS_OFFICER_ROLE" "$KEY_VAULT_ID" "deploying principal [$ACCOUNT_USER_NAME]" "[$KEY_VAULT_NAME] key vault"
else
	echo "WARNING: could not resolve the object id of the deploying principal [$ACCOUNT_USER_NAME]; the [$KEY_VAULT_SECRETS_OFFICER_ROLE] role on the [$KEY_VAULT_NAME] key vault must already be assigned to it"
fi

set_secret "$SECRET_NAME" "$STORAGE_CONN_STRING"

# Retrieve secret to verify and pass to ACI
RETRIEVED_CONN_STRING=$(az keyvault secret show \
	--vault-name "$KEY_VAULT_NAME" \
	--name "$SECRET_NAME" \
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
# Step 9: Get ACR Login Server and Credentials
# =============================================================================
echo ""
echo "============================================================"
echo "Step 9: Retrieving ACR credentials..."
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

if az container show --name "$ACI_GROUP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	# The container group runs the image tag the script has just pushed again: restarting it pulls the new image
	echo "ACI container group [$ACI_GROUP_NAME] already exists: restarting it to run the image just pushed..."
	if az container restart --name "$ACI_GROUP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors 1>/dev/null; then
		echo "ACI container group [$ACI_GROUP_NAME] restarted successfully."
	else
		echo "Failed to restart ACI container group [$ACI_GROUP_NAME]."
		exit 1
	fi
else
	if [ "$USE_ACR_IMAGE" = true ]; then
		az container create \
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
			--dns-name-label "$ACI_GROUP_NAME" \
			--ports 80 \
			--cpu 1 --memory 1 \
			--os-type Linux \
			--restart-policy Always \
			--location "$LOCATION" \
			--only-show-errors 1>/dev/null
	else
		az container create \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--name "$ACI_GROUP_NAME" \
			--image "$FULL_IMAGE" \
			--environment-variables \
				AZURE_STORAGE_CONNECTION_STRING="$RETRIEVED_CONN_STRING" \
				BLOB_CONTAINER_NAME="$BLOB_CONTAINER_NAME" \
				LOGIN_NAME="$LOGIN_NAME" \
			--ip-address Public \
			--dns-name-label "$ACI_GROUP_NAME" \
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
echo "FQDN:              ${ACI_GROUP_NAME}.${LOCATION}.azurecontainer.io"
echo ""
echo "Run 'bash scripts/validate.sh' to verify the deployment."
echo "============================================================"
