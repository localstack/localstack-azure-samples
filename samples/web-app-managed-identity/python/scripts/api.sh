#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
NEW_LOCATION='northeurope'
RANDOM_SUFFIX=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 4)
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}-${RANDOM_SUFFIX}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
PROXY_PORT=$(curl http://localhost:4566/_localstack/proxy -s | jq '.proxy_port')
SUB_BASE_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.ManagedIdentity/userAssignedIdentities"
RG_BASE_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.ManagedIdentity/userAssignedIdentities"
ENVIRONMENT=$(az account show --query environmentName --output tsv)
API_VERSION="2024-11-30"

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	CURL="env http_proxy=http://127.0.0.1:$PROXY_PORT https_proxy=http://127.0.0.1:$PROXY_PORT curl -k -s"
else
	CURL="curl -s"
fi

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

# Get security token
TOKEN=$(az account get-access-token --resource=https://management.azure.com/ --query accessToken --output tsv)

# Create a new user-assigned managed identity
echo "Creating user-assigned managed identity [$MANAGED_IDENTITY_NAME]..."
$CURL \
	-X PUT \
	-H "Content-Type: application/json" \
	-H "Authorization: Bearer $TOKEN" \
	-d '{
				"location": "'"$LOCATION"'",
				"tags": {
					"environment": "test",
					"mode": "REST API"
				}
			}' \
	"$RG_BASE_URL/$MANAGED_IDENTITY_NAME?api-version=$API_VERSION" | jq -r .


if [ $? -eq 0 ]; then
	echo "User-assigned managed identity [$MANAGED_IDENTITY_NAME] created successfully."
else
	echo "Failed to create user-assigned managed identity [$MANAGED_IDENTITY_NAME]."
	exit 1
fi

# Get the user-assigned managed identity
echo "Retrieving user-assigned managed identity [$MANAGED_IDENTITY_NAME]..."
$CURL \
	-X GET \
	-H "Authorization: Bearer $TOKEN" \
	"$RG_BASE_URL/$MANAGED_IDENTITY_NAME?api-version=$API_VERSION" | jq -r .

if [ $? -eq 0 ]; then
	echo "User-assigned managed identity [$MANAGED_IDENTITY_NAME] retrieved successfully."
else
	echo "Failed to retrieve user-assigned managed identity [$MANAGED_IDENTITY_NAME]."
	exit 1
fi

# List all user-assigned managed identities in the resource group
echo "Listing all user-assigned managed identities in resource group [$RESOURCE_GROUP_NAME]..."
$CURL \
	-X GET \
	-H "Authorization: Bearer $TOKEN" \
	"$RG_BASE_URL?api-version=$API_VERSION" | jq -r .

if [ $? -eq 0 ]; then
	echo "User-assigned managed identities listed successfully."
else
	echo "Failed to list user-assigned managed identities."
	exit 1
fi

# List all user-assigned managed identities in the subscription
echo "Listing all user-assigned managed identities in the subscription..."
$CURL \
	-X GET \
	-H "Authorization: Bearer $TOKEN" \
	"$SUB_BASE_URL?api-version=$API_VERSION" | jq -r .

if [ $? -eq 0 ]; then
	echo "User-assigned managed identities in the subscription listed successfully."
else
	echo "Failed to list user-assigned managed identities in the subscription."
	exit 1
fi

# Update the user-assigned managed identity
echo "Updating user-assigned managed identity [$MANAGED_IDENTITY_NAME]..."
$CURL \
	-X PATCH \
	-H "Content-Type: application/json" \
	-H "Authorization: Bearer $TOKEN" \
	-d '{
				"location": "'"$NEW_LOCATION"'",
				"tags": {
					"environment": "LocalStack",
					"mode": "Azure REST API"
				}
			}' \
	"$RG_BASE_URL/$MANAGED_IDENTITY_NAME?api-version=$API_VERSION" | jq -r .


if [ $? -eq 0 ]; then
	echo "User-assigned managed identity [$MANAGED_IDENTITY_NAME] updated successfully."
else
	echo "Failed to update user-assigned managed identity [$MANAGED_IDENTITY_NAME]."
	exit 1
fi

# Delete the user-assigned managed identity
echo "Deleting user-assigned managed identity [$MANAGED_IDENTITY_NAME]..."
$CURL \
	-X DELETE \
	-H "Authorization: Bearer $TOKEN" \
	"$RG_BASE_URL/$MANAGED_IDENTITY_NAME?api-version=$API_VERSION" >/dev/null

if [ $? -eq 0 ]; then
	echo "User-assigned managed identity [$MANAGED_IDENTITY_NAME] deleted successfully."
else
	echo "Failed to delete user-assigned managed identity [$MANAGED_IDENTITY_NAME]."
	exit 1
fi