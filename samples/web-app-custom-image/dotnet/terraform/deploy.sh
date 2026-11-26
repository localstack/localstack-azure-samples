#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="custom-image-webapp"
IMAGE_TAG="v1"

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

# Intialize Terraform
echo "Initializing Terraform..."
terraform init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
        -var "prefix=$PREFIX" \
        -var "suffix=$SUFFIX" \
        -var "location=$LOCATION" \
				-var "image_name=$IMAGE_NAME" \
				-var "image_tag=$IMAGE_TAG"

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
WEB_APP_NAME=$(terraform output -raw web_app_name)
ACR_NAME=$(terraform output -raw container_registry_name)

if [[ -z "$RESOURCE_GROUP_NAME" || -z "$WEB_APP_NAME" || -z "$ACR_NAME" ]]; then
	echo "Resource Group Name, Web App Name, or ACR Name is empty. Exiting."
	exit 1
fi

# Print the list of resources in the resource group
echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table 