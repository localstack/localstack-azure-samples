#!/bin/bash

# Enable verbose debugging
set -x

# Variables
PREFIX='local'
SUFFIX='test'
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
RESOURCE_GROUP_NAME="$PREFIX-aci-rg"
LOCATION="eastus"
VALIDATE_TEMPLATE=1
USE_WHAT_IF=0
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="vacation-planner"
IMAGE_TAG="v1"

echo "=================================================="
echo "DEBUG: Starting bicep deployment for aci-blob-storage"
echo "DEBUG: Resource Group: $RESOURCE_GROUP_NAME"
echo "DEBUG: Environment: $ENVIRONMENT"
echo "=================================================="

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit
# Validates if the resource group exists in the subscription, if not creates it
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	# Create the resource group
	az group create \
		--name $RESOURCE_GROUP_NAME \
		--location $LOCATION \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created in the subscription [$SUBSCRIPTION_NAME]"
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]"
		exit
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists in the subscription [$SUBSCRIPTION_NAME]"
fi

# =============================================================================
# Build and push the Docker image before Bicep deployment
# (Bicep creates the ACI group referencing the image in ACR)
# =============================================================================

# Create ACR first so we can push the image
ACR_NAME="${PREFIX}aciacr${SUFFIX}"
echo "Creating ACR [$ACR_NAME] for image push..."
az acr create \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--sku Basic \
	--admin-enabled true \
	--only-show-errors 1>/dev/null

LOGIN_SERVER=$(az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "loginServer" \
	--output tsv \
	--only-show-errors)

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

FULL_IMAGE="${LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building Docker image [$IMAGE_NAME:$IMAGE_TAG]..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" ../src/

if [[ $? != 0 ]]; then
	echo "Failed to build Docker image."
	exit 1
fi

docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "$FULL_IMAGE"

echo "Logging in to ACR [$LOGIN_SERVER]..."
echo "$ACR_PASSWORD" | docker login "$LOGIN_SERVER" --username "$ACR_USERNAME" --password-stdin 2>/dev/null

echo "Pushing image [$FULL_IMAGE]..."
docker push "$FULL_IMAGE" 2>/dev/null

if [[ $? != 0 ]]; then
	echo "Failed to push image to ACR."
	exit 1
fi
echo "Image pushed to ACR successfully."

# =============================================================================
# Validate and deploy the Bicep template
# =============================================================================

# Validates the Bicep template
if [[ $VALIDATE_TEMPLATE == 1 ]]; then
	if [[ $USE_WHAT_IF == 1 ]]; then
		# Execute a deployment What-If operation at resource group scope.
		echo "Previewing changes deployed by Bicep template [$TEMPLATE]..."
		az deployment group what-if \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $TEMPLATE \
			--parameters $PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			--only-show-errors

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			exit
		fi
	else
		# Validate the Bicep template
		echo "Validating Bicep template [$TEMPLATE]..."
		output=$(az deployment group validate \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $TEMPLATE \
			--parameters $PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			--only-show-errors)

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			echo "$output"
			exit
		fi
	fi
fi

# Deploy the Bicep template
echo "Deploying Bicep template [$TEMPLATE]..."
if DEPLOYMENT_OUTPUTS=$(az deployment group create \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors \
	--template-file $TEMPLATE \
	--parameters $PARAMETERS \
	--parameters location=$LOCATION \
	prefix=$PREFIX \
	suffix=$SUFFIX \
	--query 'properties.outputs' -o json); then
	echo "Bicep template [$TEMPLATE] deployed successfully. Outputs:"
	# Strip any non-JSON prefix (e.g. Bicep CLI messages) before parsing
	DEPLOYMENT_JSON=$(echo "$DEPLOYMENT_OUTPUTS" | sed -n '/{/,$p')
	echo "$DEPLOYMENT_JSON" | jq .
	STORAGE_ACCOUNT_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.storageAccountName.value')
	KEY_VAULT_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.keyVaultName.value')
	ACR_LOGIN_SERVER=$(echo "$DEPLOYMENT_JSON" | jq -r '.acrLoginServer.value')
	ACI_GROUP_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.aciGroupName.value')
	FQDN=$(echo "$DEPLOYMENT_JSON" | jq -r '.fqdn.value')
	echo "Deployment details:"
	echo "- storageAccountName: $STORAGE_ACCOUNT_NAME"
	echo "- keyVaultName: $KEY_VAULT_NAME"
	echo "- acrLoginServer: $ACR_LOGIN_SERVER"
	echo "- aciGroupName: $ACI_GROUP_NAME"
	echo "- fqdn: $FQDN"
else
	echo "Failed to deploy Bicep template [$TEMPLATE]"
	exit 1
fi
