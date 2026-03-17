#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='eastus'
IMAGE_NAME='vacation-planner'
IMAGE_TAG='v1'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	AZ="azlocal"
else
	echo "Using standard terraform and az for AzureCloud environment."
	AZ="az"
fi

# =============================================================================
# Build and push the Docker image before Terraform deployment
# (Terraform references the pre-created ACR as a data source)
# =============================================================================

# Create resource group and ACR first so we can push the image
RESOURCE_GROUP_NAME="${PREFIX}-aci-rg"
ACR_NAME="${PREFIX}aciacr${SUFFIX}"

echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
$AZ group create \
	--name "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--only-show-errors 1>/dev/null

echo "Creating ACR [$ACR_NAME] for image push..."
$AZ acr create \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--sku Basic \
	--admin-enabled true \
	--only-show-errors 1>/dev/null

LOGIN_SERVER=$($AZ acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "loginServer" \
	--output tsv \
	--only-show-errors)

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
# Terraform init, plan, and apply
# =============================================================================

echo "Initializing Terraform..."
terraform init -upgrade

# Import the resource group that was pre-created for the image push
echo "Importing pre-created resource group into Terraform state..."
terraform import \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "image_name=$IMAGE_NAME" \
	-var "image_tag=$IMAGE_TAG" \
	azurerm_resource_group.example \
	"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/${RESOURCE_GROUP_NAME}" 2>/dev/null || true

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "image_name=$IMAGE_NAME" \
	-var "image_tag=$IMAGE_TAG"

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
terraform apply -auto-approve tfplan

if [[ $? != 0 ]]; then
	echo "Terraform apply failed. Exiting."
	exit 1
fi

# Get the output values
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
STORAGE_ACCOUNT_NAME=$(terraform output -raw storage_account_name)
ACR_NAME=$(terraform output -raw acr_name)
ACI_GROUP_NAME=$(terraform output -raw aci_group_name)
FQDN=$(terraform output -raw fqdn)

echo ""
echo "============================================================"
echo "Deployment Complete!"
echo "============================================================"
echo "Resource Group:    $RESOURCE_GROUP_NAME"
echo "Storage Account:   $STORAGE_ACCOUNT_NAME"
echo "ACR:               $ACR_NAME"
echo "ACI Container:     $ACI_GROUP_NAME"
echo "FQDN:              $FQDN"
echo "============================================================"
