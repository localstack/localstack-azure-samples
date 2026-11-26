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

# Dual-target provider configuration. providers.tf hardcodes nothing: the azurerm provider reads its endpoints and the
# target subscription from the ARM_* environment variables exported here.
# - On both targets: the subscription and tenant of the active az account.
# - Only when the active az cloud is LocalStack: the emulator's metadata endpoint, taken from the az cloud registration
#   that `lstk az start-interception` created, so nothing is hardcoded here either.
ACTIVE_CLOUD=$(az cloud show --query name --output tsv --only-show-errors)
ARM_SUBSCRIPTION_ID=$(az account show --query id --output tsv --only-show-errors)
ARM_TENANT_ID=$(az account show --query tenantId --output tsv --only-show-errors)
export ARM_SUBSCRIPTION_ID ARM_TENANT_ID

if [[ $ACTIVE_CLOUD == "LocalStack" ]]; then
	RESOURCE_MANAGER_ENDPOINT=$(az cloud show --query endpoints.resourceManager --output tsv --only-show-errors)
	METADATA_HOSTNAME="${RESOURCE_MANAGER_ENDPOINT#https://}"
	export ARM_METADATA_HOSTNAME="${METADATA_HOSTNAME%/}"
	echo "Active cloud is [$ACTIVE_CLOUD]: Terraform targets the emulator at [$RESOURCE_MANAGER_ENDPOINT]"
else
	# Cleared rather than merely not set: a value inherited from an earlier emulator deployment in the same shell would
	# keep the provider doing metadata discovery against the emulator while the CLI is on Azure.
	unset ARM_METADATA_HOSTNAME
	echo "Active cloud is [$ACTIVE_CLOUD]: Terraform targets Azure subscription [$ARM_SUBSCRIPTION_ID]"
fi

# =============================================================================
# Build and push the Docker image before Terraform deployment
# (Terraform references the pre-created ACR as a data source)
# =============================================================================

# Create resource group and ACR first so we can push the image
RESOURCE_GROUP_NAME="${PREFIX}-aca-rg"
ACR_NAME="${PREFIX}acaacr${SUFFIX}"

# Stop if the Terraform state of a previous run tracks another resource group: run under another PREFIX, the
# apply would replace that run's resource group and delete its resources
echo "Checking that the Terraform state tracks no resource group other than [$RESOURCE_GROUP_NAME]..."
STATE_RESOURCE_GROUP_NAME=$(terraform state show -no-color azurerm_resource_group.example 2>/dev/null | awk '$1 == "name" { gsub(/"/, "", $3); print $3 }')

if [[ -n $STATE_RESOURCE_GROUP_NAME && $STATE_RESOURCE_GROUP_NAME != "$RESOURCE_GROUP_NAME" ]]; then
	echo "The Terraform state tracks the [$STATE_RESOURCE_GROUP_NAME] resource group of a previous run: delete its terraform.tfstate files, or run with the PREFIX of that run"
	exit 1
fi

if az group show --name "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	echo "[$RESOURCE_GROUP_NAME] resource group already exists"
else
	echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
	az group create \
		--name "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$RESOURCE_GROUP_NAME] resource group successfully created"
	else
		echo "Failed to create [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
fi

if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	echo "[$ACR_NAME] container registry already exists in the [$RESOURCE_GROUP_NAME] resource group"
else
	echo "Creating ACR [$ACR_NAME] for image push..."
	az acr create \
		--name "$ACR_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--sku Basic \
		--admin-enabled true \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$ACR_NAME] container registry successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$ACR_NAME] container registry in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
fi

LOGIN_SERVER=$(az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "loginServer" \
	--output tsv \
	--only-show-errors)

if [[ -n $LOGIN_SERVER ]]; then
	echo "Successfully retrieved the login server of the [$ACR_NAME] container registry"
else
	echo "Failed to retrieve the login server of the [$ACR_NAME] container registry"
	exit 1
fi

ACR_USERNAME=$(az acr credential show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "username" \
	--output tsv \
	--only-show-errors)

if [[ -n $ACR_USERNAME ]]; then
	echo "Successfully retrieved the admin username of the [$ACR_NAME] container registry"
else
	echo "Failed to retrieve the admin username of the [$ACR_NAME] container registry"
	exit 1
fi

ACR_PASSWORD=$(az acr credential show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "passwords[0].value" \
	--output tsv \
	--only-show-errors)

if [[ -n $ACR_PASSWORD ]]; then
	echo "Successfully retrieved the admin password of the [$ACR_NAME] container registry"
else
	echo "Failed to retrieve the admin password of the [$ACR_NAME] container registry"
	exit 1
fi

FULL_IMAGE="${LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building Docker image [$IMAGE_NAME:$IMAGE_TAG]..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" ../src/

if [[ $? != 0 ]]; then
	echo "Failed to build Docker image."
	exit 1
fi

docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "$FULL_IMAGE"

if [[ $? != 0 ]]; then
	echo "Failed to tag Docker image."
	exit 1
fi

echo "Logging in to ACR [$LOGIN_SERVER]..."
echo "$ACR_PASSWORD" | docker login "$LOGIN_SERVER" --username "$ACR_USERNAME" --password-stdin 2>/dev/null

if [[ $? != 0 ]]; then
	echo "Failed to log in to ACR."
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
terraform init -upgrade

if [[ $? != 0 ]]; then
	echo "Terraform init failed. Exiting."
	exit 1
fi

# Import the resource group that was pre-created for the image push, unless a previous run already did
echo "Checking if the [$RESOURCE_GROUP_NAME] resource group is in the Terraform state..."
terraform state show azurerm_resource_group.example &>/dev/null

if [[ $? == 0 ]]; then
	echo "[$RESOURCE_GROUP_NAME] resource group already exists in the Terraform state"
else
	echo "Importing the pre-created [$RESOURCE_GROUP_NAME] resource group into the Terraform state..."
	terraform import \
		-var "prefix=$PREFIX" \
		-var "suffix=$SUFFIX" \
		-var "location=$LOCATION" \
		-var "image_name=$IMAGE_NAME" \
		-var "image_tag=$IMAGE_TAG" \
		-var "managed_identity_type=$MANAGED_IDENTITY_TYPE" \
		azurerm_resource_group.example \
		"/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}"

	if [[ $? == 0 ]]; then
		echo "[$RESOURCE_GROUP_NAME] resource group successfully imported into the Terraform state"
	else
		echo "Failed to import [$RESOURCE_GROUP_NAME] resource group into the Terraform state"
		exit 1
	fi
fi

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "image_name=$IMAGE_NAME" \
	-var "image_tag=$IMAGE_TAG" \
	-var "managed_identity_type=$MANAGED_IDENTITY_TYPE"

if [[ $? != 0 ]]; then
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
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
STORAGE_ACCOUNT_NAME=$(terraform output -raw storage_account_name)
ACR_NAME=$(terraform output -raw acr_name)
ENVIRONMENT_NAME=$(terraform output -raw environment_name)
APP_NAME=$(terraform output -raw app_name)
FQDN=$(terraform output -raw fqdn)
PRINCIPAL_ID=$(terraform output -raw principal_id)

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
