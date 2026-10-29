#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX='test'
LOCATION='eastus'
IMAGE_NAME='guestbook'
IMAGE_TAG='v1'
MANAGED_IDENTITY_TYPE="${MANAGED_IDENTITY_TYPE:-None}"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# =============================================================================
# Build and push the Docker image before Terraform deployment
# (Terraform references the pre-created ACR as a data source)
# =============================================================================

# Create resource group and ACR first so we can push the image
RESOURCE_GROUP_NAME="${PREFIX}-aca-rg"
ACR_NAME="${PREFIX}acaacr${SUFFIX}"

echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
if ! az group create \
	--name "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--only-show-errors 1>/dev/null; then
	echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
	exit 1
fi

echo "Creating ACR [$ACR_NAME] for image push..."
if ! az acr create \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--sku Basic \
	--admin-enabled true \
	--only-show-errors 1>/dev/null; then
	echo "Failed to create ACR [$ACR_NAME]."
	exit 1
fi

if ! LOGIN_SERVER=$(az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "loginServer" \
	--output tsv \
	--only-show-errors); then
	echo "Failed to retrieve the login server of ACR [$ACR_NAME]."
	exit 1
fi

if ! ACR_USERNAME=$(az acr credential show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "username" \
	--output tsv \
	--only-show-errors); then
	echo "Failed to retrieve the admin username of ACR [$ACR_NAME]."
	exit 1
fi

if ! ACR_PASSWORD=$(az acr credential show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "passwords[0].value" \
	--output tsv \
	--only-show-errors); then
	echo "Failed to retrieve the admin password of ACR [$ACR_NAME]."
	exit 1
fi

FULL_IMAGE="${LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building Docker image [$IMAGE_NAME:$IMAGE_TAG]..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" ../src/

if [[ $? != 0 ]]; then
	echo "Failed to build Docker image."
	exit 1
fi

if ! docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "$FULL_IMAGE"; then
	echo "Failed to tag Docker image [$IMAGE_NAME:$IMAGE_TAG] as [$FULL_IMAGE]."
	exit 1
fi

echo "Logging in to ACR [$LOGIN_SERVER]..."
if ! echo "$ACR_PASSWORD" | docker login "$LOGIN_SERVER" --username "$ACR_USERNAME" --password-stdin 2>/dev/null; then
	echo "Failed to log in to ACR [$LOGIN_SERVER]."
	exit 1
fi

echo "Pushing image [$FULL_IMAGE]..."
docker push "$FULL_IMAGE" 2>/dev/null

if [[ $? != 0 ]]; then
	echo "Failed to push image to ACR."
	exit 1
fi
echo "Image pushed to ACR successfully."

# =============================================================================
# Terraform init, plan, and apply
# =============================================================================

echo "Initializing Terraform..."
if ! terraform init -upgrade; then
	echo "Failed to initialize Terraform."
	exit 1
fi

# Import the resource group that was pre-created for the image push
echo "Importing pre-created resource group into Terraform state..."
# A re-run finds the group in the state already, and import refuses it; every other failure stops the deploy.
if terraform state show azurerm_resource_group.example >/dev/null 2>&1; then
	echo "Resource group [$RESOURCE_GROUP_NAME] is already in the Terraform state."
elif ! terraform import \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "image_name=$IMAGE_NAME" \
	-var "image_tag=$IMAGE_TAG" \
	-var "managed_identity_type=$MANAGED_IDENTITY_TYPE" \
	azurerm_resource_group.example \
	"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/${RESOURCE_GROUP_NAME}"; then
	echo "Failed to import resource group [$RESOURCE_GROUP_NAME] into the Terraform state."
	exit 1
fi

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
if ! terraform plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "image_name=$IMAGE_NAME" \
	-var "image_tag=$IMAGE_TAG" \
	-var "managed_identity_type=$MANAGED_IDENTITY_TYPE"; then
	echo "Terraform plan failed. Exiting."
	exit 1
fi

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
terraform apply -auto-approve tfplan

if [[ $? != 0 ]]; then
	echo "Terraform apply failed. Exiting."
	exit 1
fi

# Get the output values
if ! RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name); then
	echo "Failed to read the Terraform output [resource_group_name]."
	exit 1
fi
if ! STORAGE_ACCOUNT_NAME=$(terraform output -raw storage_account_name); then
	echo "Failed to read the Terraform output [storage_account_name]."
	exit 1
fi
if ! ACR_NAME=$(terraform output -raw acr_name); then
	echo "Failed to read the Terraform output [acr_name]."
	exit 1
fi
if ! ENVIRONMENT_NAME=$(terraform output -raw environment_name); then
	echo "Failed to read the Terraform output [environment_name]."
	exit 1
fi
if ! APP_NAME=$(terraform output -raw app_name); then
	echo "Failed to read the Terraform output [app_name]."
	exit 1
fi
if ! FQDN=$(terraform output -raw fqdn); then
	echo "Failed to read the Terraform output [fqdn]."
	exit 1
fi
if ! PRINCIPAL_ID=$(terraform output -raw principal_id); then
	echo "Failed to read the Terraform output [principal_id]."
	exit 1
fi

echo ""
echo "============================================================"
echo "Deployment Complete!"
echo "============================================================"
echo "Resource Group:    $RESOURCE_GROUP_NAME"
echo "Storage Account:   $STORAGE_ACCOUNT_NAME"
echo "ACR:               $ACR_NAME"
echo "ACA Environment:   $ENVIRONMENT_NAME"
echo "Container App:     $APP_NAME"
echo "Ingress FQDN:      $FQDN"
echo "Managed Identity:  $MANAGED_IDENTITY_TYPE $PRINCIPAL_ID"
echo "============================================================"
