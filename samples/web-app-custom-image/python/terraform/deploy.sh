#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="custom-image-webapp"
IMAGE_TAG="v1"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

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