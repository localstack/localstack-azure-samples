#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RANDOM_SUFFIX=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 4)
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}-${RANDOM_SUFFIX}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

# Create a resource group
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	# Create the resource group
	az group create \
		--name $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
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

# Create a new user-assigned managed identity
echo "Creating user-assigned managed identity [$MANAGED_IDENTITY_NAME]..."
az identity create \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--tags environment="$ENVIRONMENT" \
	--only-show-errors 

if [ $? -eq 0 ]; then
	echo "User-assigned managed identity [$MANAGED_IDENTITY_NAME] created successfully."
else
	echo "Failed to create user-assigned managed identity [$MANAGED_IDENTITY_NAME]."
	exit 1
fi

# Get the user-assigned managed identity
echo "Retrieving user-assigned managed identity [$MANAGED_IDENTITY_NAME]..."
az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors

if [ $? -eq 0 ]; then
	echo "User-assigned managed identity [$MANAGED_IDENTITY_NAME] retrieved successfully."
else
	echo "Failed to retrieve user-assigned managed identity [$MANAGED_IDENTITY_NAME]."
	exit 1
fi

# List all user-assigned managed identities in the resource group
echo "Listing all user-assigned managed identities in resource group [$RESOURCE_GROUP_NAME]..."
az identity list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors

if [ $? -eq 0 ]; then
	echo "User-assigned managed identities listed successfully."
else
	echo "Failed to list user-assigned managed identities."
	exit 1
fi

# Delete the user-assigned managed identity
echo "Deleting user-assigned managed identity [$MANAGED_IDENTITY_NAME]..."
az identity delete \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors

if [ $? -eq 0 ]; then
	echo "User-assigned managed identity [$MANAGED_IDENTITY_NAME] deleted successfully."
else
	echo "Failed to delete user-assigned managed identity [$MANAGED_IDENTITY_NAME]."
	exit 1
fi