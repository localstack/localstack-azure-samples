#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
ACR_NAME="${PREFIX}acr${SUFFIX}"
ACR_SKU='Premium'
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="S1"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
IMAGE_NAME="custom-image-webapp"
IMAGE_TAG="v1"
LOCAL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
VIRTUAL_NETWORK_NAME="${PREFIX}-vnet-${SUFFIX}"
VIRTUAL_NETWORK_ADDRESS_PREFIX="10.0.0.0/8"
WEB_APP_SUBNET_NAME="app-subnet"
WEB_APP_SUBNET_PREFIX="10.0.0.0/24"
WEB_APP_SUBNET_NSG_NAME="${PREFIX}-webapp-subnet-nsg-${SUFFIX}"
PE_SUBNET_NAME="pe-subnet"
PE_SUBNET_PREFIX="10.0.1.0/24"
PE_SUBNET_NSG_NAME="${PREFIX}-pe-subnet-nsg-${SUFFIX}"
VIRTUAL_NETWORK_LINK_NAME="link-to-vnet"
PRIVATE_DNS_ZONE_NAME="privatelink.azurecr.io"
PRIVATE_ENDPOINT_NAME="${PREFIX}-acr-pe-${SUFFIX}"
PRIVATE_ENDPOINT_GROUP="registry"
PRIVATE_DNS_ZONE_GROUP_NAME="default"
NAT_GATEWAY_NAME="${PREFIX}-nat-gateway-${SUFFIX}"
PIP_PREFIX_NAME="${PREFIX}-nat-gateway-pip-prefix-${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
DIAGNOSTIC_SETTINGS_NAME='default'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
RETRY_COUNT=3
SLEEP=5

cd "$CURRENT_DIR" || exit

# Create a resource group
echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
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

# Check if the Azure Container Registry already exists
echo "Checking if [$ACR_NAME] Azure Container Registry already exists in the [$RESOURCE_GROUP_NAME] resource group..."
az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$ACR_NAME] Azure Container Registry exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating Azure Container Registry [$ACR_NAME]..."
	az acr create \
		--name "$ACR_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--sku "$ACR_SKU" \
		--admin-enabled true \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Azure Container Registry [$ACR_NAME] created successfully."
	else
		echo "Failed to create Azure Container Registry [$ACR_NAME]."
		exit 1
	fi
else
	echo "[$ACR_NAME] Azure Container Registry already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Get the Azure Container Registry resource id
echo "Getting [$ACR_NAME] Azure Container Registry resource id in the [$RESOURCE_GROUP_NAME] resource group..."
ACR_ID=$(az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $ACR_ID ]]; then
	echo "[$ACR_NAME] Azure Container Registry resource id retrieved successfully: $ACR_ID"
else
	echo "Failed to retrieve [$ACR_NAME] Azure Container Registry resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

echo "Logging into Azure Container Registry [$ACR_NAME]..."
az acr login --name "$ACR_NAME" --only-show-errors

if [ $? -eq 0 ]; then
	echo "Logged into Azure Container Registry [$ACR_NAME] successfully."
else
	echo "Failed to log into Azure Container Registry [$ACR_NAME]."
	exit 1
fi

echo "Getting login server for Azure Container Registry [$ACR_NAME]..."
ACR_LOGIN_SERVER=$(az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "loginServer" \
	--output tsv \
	--only-show-errors)

if [ -n "$ACR_LOGIN_SERVER" ]; then
	echo "Login server retrieved successfully: $ACR_LOGIN_SERVER"
else
	echo "Failed to retrieve login server for Azure Container Registry [$ACR_NAME]."
	exit 1
fi

# Create full image name with login server, image name, and tag
FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building custom Docker image [$LOCAL_IMAGE]..."
docker build -t "$LOCAL_IMAGE" ../src/

if [ $? -eq 0 ]; then
	echo "Docker image [$LOCAL_IMAGE] built successfully."
else
	echo "Failed to build Docker image [$LOCAL_IMAGE]."
	exit 1
fi

echo "Tagging Docker image [$LOCAL_IMAGE] as [$FULL_IMAGE]..."
docker tag "$LOCAL_IMAGE" "$FULL_IMAGE"

if [ $? -eq 0 ]; then
	echo "Docker image [$LOCAL_IMAGE] tagged as [$FULL_IMAGE] successfully."
else
	echo "Failed to tag Docker image [$LOCAL_IMAGE] as [$FULL_IMAGE]."
	exit 1
fi

echo "Pushing image [$FULL_IMAGE] to ACR..."
docker push "$FULL_IMAGE"

if [ $? -eq 0 ]; then
	echo "Docker image [$FULL_IMAGE] pushed to ACR successfully."
else
	echo "Failed to push Docker image [$FULL_IMAGE] to ACR."
	exit 1
fi

# Check if the user-assigned managed identity already exists
echo "Checking if [$MANAGED_IDENTITY_NAME] user-assigned managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group..."

az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$MANAGED_IDENTITY_NAME] user-assigned managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$MANAGED_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the user-assigned managed identity
	az identity create \
		--name "$MANAGED_IDENTITY_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--subscription "$SUBSCRIPTION_ID" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$MANAGED_IDENTITY_NAME] user-assigned managed identity successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$MANAGED_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$MANAGED_IDENTITY_NAME] user-assigned managed identity already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Retrieve the principalId of the user-assigned managed identity
echo "Retrieving principalId for [$MANAGED_IDENTITY_NAME] managed identity..."
PRINCIPAL_ID=$(az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query principalId \
	--output tsv)

if [[ -n $PRINCIPAL_ID ]]; then
	echo "[$PRINCIPAL_ID] principalId  for the [$MANAGED_IDENTITY_NAME] managed identity successfully retrieved"
else
	echo "Failed to retrieve principalId for the [$MANAGED_IDENTITY_NAME] managed identity"
	exit 1
fi

# Retrieve the clientId of the user-assigned managed identity
echo "Retrieving clientId for [$MANAGED_IDENTITY_NAME] managed identity..."
CLIENT_ID=$(az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query clientId \
	--output tsv)

if [[ -n $CLIENT_ID ]]; then
	echo "[$CLIENT_ID] clientId  for the [$MANAGED_IDENTITY_NAME] managed identity successfully retrieved"
else
	echo "Failed to retrieve clientId for the [$MANAGED_IDENTITY_NAME] managed identity"
	exit 1
fi

# Retrieve the resource id of the user-assigned managed identity
echo "Retrieving resource id for the [$MANAGED_IDENTITY_NAME] managed identity..."
IDENTITY_ID=$(az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv)

if [[ -n $IDENTITY_ID ]]; then
	echo "Resource id for the [$MANAGED_IDENTITY_NAME] managed identity successfully retrieved"
else
	echo "Failed to retrieve the resource id for the [$MANAGED_IDENTITY_NAME] managed identity"
	exit 1
fi

# Assign the AcrPull role to the managed identity with the Azure Container Registry as scope
ROLE="AcrPull"
echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity has the [$ROLE] role assignment on Azure Container Registry [$ACR_NAME]..."
current=$(az role assignment list \
	--assignee "$PRINCIPAL_ID" \
	--scope "$ACR_ID" \
	--query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == "$ROLE" ]]; then
	echo "Managed identity [$MANAGED_IDENTITY_NAME] already has the [$ROLE] role assignment on Azure Container Registry [$ACR_NAME]"
else
	echo "Managed identity [$MANAGED_IDENTITY_NAME] does not have the [$ROLE] role assignment on Azure Container Registry [$ACR_NAME]"
	echo "Creating role assignment: assigning [$ROLE] role to managed identity [$MANAGED_IDENTITY_NAME] on Azure Container Registry [$ACR_NAME]..."
	ATTEMPT=1
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		az role assignment create \
			--assignee "$PRINCIPAL_ID" \
			--role "$ROLE" \
			--scope "$ACR_ID" 1>/dev/null

		if [[ $? == 0 ]]; then
			break
		else
			if [ $ATTEMPT -lt $RETRY_COUNT ]; then
				echo "Role assignment failed. Waiting [$SLEEP] seconds before retry..."
				sleep $SLEEP
			fi
			ATTEMPT=$((ATTEMPT + 1))
		fi
	done

	if [[ $? == 0 ]]; then
		echo "Successfully assigned [$ROLE] role to managed identity [$MANAGED_IDENTITY_NAME] on Azure Container Registry [$ACR_NAME]"
	else
		echo "Failed to assign [$ROLE] role to managed identity [$MANAGED_IDENTITY_NAME] on Azure Container Registry [$ACR_NAME]"
		exit 1
	fi
fi

# Check if the network security group for the web app subnet already exists
echo "Checking if [$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az network nsg show \
	--name "$WEB_APP_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet..."

	# Create the network security group for the web app subnet
	az network nsg create \
		--name "$WEB_APP_SUBNET_NSG_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Get the resource id of the network security group for the web app subnet
echo "Getting [$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet resource id in the [$RESOURCE_GROUP_NAME] resource group..."
WEB_APP_SUBNET_NSG_ID=$(az network nsg show \
	--name "$WEB_APP_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $WEB_APP_SUBNET_NSG_ID ]]; then
	echo "[$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet resource id retrieved successfully: $WEB_APP_SUBNET_NSG_ID"
else
	echo "Failed to retrieve [$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Check if the network security group for the private endpoint subnet already exists
echo "Checking if [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az network nsg show \
	--name "$PE_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet..."

	# Create the network security group for the private endpoint subnet
	az network nsg create \
		--name "$PE_SUBNET_NSG_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Get the resource id of the network security group for the private endpoint subnet
echo "Getting [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet resource id in the [$RESOURCE_GROUP_NAME] resource group..."
PE_SUBNET_NSG_ID=$(az network nsg show \
	--name "$PE_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $PE_SUBNET_NSG_ID ]]; then
	echo "[$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet resource id retrieved successfully: $PE_SUBNET_NSG_ID"
else
	echo "Failed to retrieve [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Check if the public IP prefix for the NAT Gateway already exists
echo "Checking if [$PIP_PREFIX_NAME] public IP prefix for the NAT Gateway actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az network public-ip prefix show \
	--name "$PIP_PREFIX_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$PIP_PREFIX_NAME] public IP prefix for the NAT Gateway actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$PIP_PREFIX_NAME] public IP prefix for the NAT Gateway in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the public IP prefix for the NAT Gateway
	az network public-ip prefix create \
		--name "$PIP_PREFIX_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--length 31 \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$PIP_PREFIX_NAME] public IP prefix for the NAT Gateway successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$PIP_PREFIX_NAME] public IP prefix for the NAT Gateway in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$PIP_PREFIX_NAME] public IP prefix for the NAT Gateway already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the NAT Gateway already exists
echo "Checking if [$NAT_GATEWAY_NAME] NAT Gateway actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az network nat gateway show \
	--name "$NAT_GATEWAY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$NAT_GATEWAY_NAME] NAT Gateway actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$NAT_GATEWAY_NAME] NAT Gateway in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the NAT Gateway
	az network nat gateway create \
		--name "$NAT_GATEWAY_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--public-ip-prefixes "$PIP_PREFIX_NAME" \
		--idle-timeout 4 \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$NAT_GATEWAY_NAME] NAT Gateway successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$NAT_GATEWAY_NAME] NAT Gateway in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$NAT_GATEWAY_NAME] NAT Gateway already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the virtual network already exists
echo "Checking if [$VIRTUAL_NETWORK_NAME] virtual network actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az network vnet show \
	--name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$VIRTUAL_NETWORK_NAME] virtual network actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$VIRTUAL_NETWORK_NAME] virtual network in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the virtual network
	az network vnet create \
		--name "$VIRTUAL_NETWORK_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--address-prefixes "$VIRTUAL_NETWORK_ADDRESS_PREFIX" \
		--subnet-name "$WEB_APP_SUBNET_NAME" \
		--subnet-prefix "$WEB_APP_SUBNET_PREFIX" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$VIRTUAL_NETWORK_NAME] virtual network successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$VIRTUAL_NETWORK_NAME] virtual network in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi

	# Update the web app subnet to associate it with the NAT Gateway and the NSG
	echo "Associating [$WEB_APP_SUBNET_NAME] subnet with the [$NAT_GATEWAY_NAME] NAT Gateway and the [$WEB_APP_SUBNET_NSG_NAME] network security group..."
	az network vnet subnet update \
		--name "$WEB_APP_SUBNET_NAME" \
		--vnet-name "$VIRTUAL_NETWORK_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--nat-gateway "$NAT_GATEWAY_NAME" \
		--network-security-group "$WEB_APP_SUBNET_NSG_NAME" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$WEB_APP_SUBNET_NAME] subnet successfully associated with the [$NAT_GATEWAY_NAME] NAT Gateway and the [$WEB_APP_SUBNET_NSG_NAME] network security group"
	else
		echo "Failed to associate [$WEB_APP_SUBNET_NAME] subnet with the [$NAT_GATEWAY_NAME] NAT Gateway and the [$WEB_APP_SUBNET_NSG_NAME] network security group"
		exit 1
	fi
else
	echo "[$VIRTUAL_NETWORK_NAME] virtual network already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the subnet already exists
echo "Checking if [$PE_SUBNET_NAME] subnet actually exists in the [$VIRTUAL_NETWORK_NAME] virtual network..."
az network vnet subnet show \
	--name "$PE_SUBNET_NAME" \
	--vnet-name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$PE_SUBNET_NAME] subnet actually exists in the [$VIRTUAL_NETWORK_NAME] virtual network"
	echo "Creating [$PE_SUBNET_NAME] subnet in the [$VIRTUAL_NETWORK_NAME] virtual network..."

	# Create the subnet
	az network vnet subnet create \
		--name "$PE_SUBNET_NAME" \
		--vnet-name "$VIRTUAL_NETWORK_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--address-prefix "$PE_SUBNET_PREFIX" \
		--network-security-group "$PE_SUBNET_NSG_NAME" \
		--private-endpoint-network-policies "Disabled" \
		--private-link-service-network-policies "Disabled" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$PE_SUBNET_NAME] subnet successfully created in the [$VIRTUAL_NETWORK_NAME] virtual network"
	else
		echo "Failed to create [$PE_SUBNET_NAME] subnet in the [$VIRTUAL_NETWORK_NAME] virtual network"
		exit
	fi
else
	echo "[$PE_SUBNET_NAME] subnet already exists in the [$VIRTUAL_NETWORK_NAME] virtual network"
fi

# Retrieve the virtual network resource id
echo "Getting [$VIRTUAL_NETWORK_NAME] virtual network resource id in the [$RESOURCE_GROUP_NAME] resource group..."
VIRTUAL_NETWORK_ID=$(az network vnet show \
	--name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $VIRTUAL_NETWORK_ID ]]; then
	echo "[$VIRTUAL_NETWORK_NAME] virtual network resource id retrieved successfully: $VIRTUAL_NETWORK_ID"
else
	echo "Failed to retrieve [$VIRTUAL_NETWORK_NAME] virtual network resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Check if the private DNS Zone already exists
echo "Checking if [$PRIVATE_DNS_ZONE_NAME] private DNS zone actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az network private-dns zone show \
	--name "$PRIVATE_DNS_ZONE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$PRIVATE_DNS_ZONE_NAME] private DNS zone actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$PRIVATE_DNS_ZONE_NAME] private DNS zone in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the private DNS Zone
	az network private-dns zone create \
		--name "$PRIVATE_DNS_ZONE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$PRIVATE_DNS_ZONE_NAME] private DNS zone successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$PRIVATE_DNS_ZONE_NAME] private DNS zone in the [$RESOURCE_GROUP_NAME] resource group"
		exit
	fi
else
	echo "[$PRIVATE_DNS_ZONE_NAME] private DNS zone already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the virtual network link between the private DNS zone and the virtual network already exists
echo "Checking if [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network actually exists..."
az network private-dns link vnet show \
	--name "$VIRTUAL_NETWORK_LINK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--zone-name "$PRIVATE_DNS_ZONE_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network actually exists"

	echo "Creating [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network..."

	# Create the virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network
	az network private-dns link vnet create \
		--name "$VIRTUAL_NETWORK_LINK_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--zone-name "$PRIVATE_DNS_ZONE_NAME" \
		--virtual-network "$VIRTUAL_NETWORK_ID" \
		--registration-enabled false \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network successfully created"
	else
		echo "Failed to create [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network"
		exit
	fi
else
	echo "[$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$PRIVATE_DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network already exists"
fi

# Check if the private endpoint already exists
echo "Checking if private endpoint [$PRIVATE_ENDPOINT_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group..."
privateEndpointId=$(az network private-endpoint list \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors \
	--query "[?name=='$PRIVATE_ENDPOINT_NAME'].id" \
	--output tsv)

if [[ -z $privateEndpointId ]]; then
	echo "Private endpoint [$PRIVATE_ENDPOINT_NAME] does not exist in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$PRIVATE_ENDPOINT_NAME] private endpoint for the [$ACR_NAME] Azure Container Registry in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create a private endpoint for the Azure Container Registry
	az network private-endpoint create \
		--name "$PRIVATE_ENDPOINT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--vnet-name "$VIRTUAL_NETWORK_NAME" \
		--subnet "$PE_SUBNET_NAME" \
		--private-connection-resource-id "$ACR_ID" \
		--group-id "$PRIVATE_ENDPOINT_GROUP" \
		--connection-name "acr-connection" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Private endpoint [$PRIVATE_ENDPOINT_NAME] successfully created for the [$ACR_NAME] Azure Container Registry in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create a private endpoint for the [$ACR_NAME] Azure Container Registry in the [$RESOURCE_GROUP_NAME] resource group"
		exit
	fi
else
	echo "Private endpoint [$PRIVATE_ENDPOINT_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the private DNS zone group is already created for the Azure Container Registry private endpoint
echo "Checking if the private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PRIVATE_ENDPOINT_NAME] private endpoint already exists..."
NAME=$(az network private-endpoint dns-zone-group show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--endpoint-name "$PRIVATE_ENDPOINT_NAME" \
	--name "$PRIVATE_DNS_ZONE_GROUP_NAME" \
	--query name \
	--output tsv \
	--only-show-errors)

if [[ -z $NAME ]]; then
	echo "No private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PRIVATE_ENDPOINT_NAME] private endpoint actually exists"
	echo "Creating private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PRIVATE_ENDPOINT_NAME] private endpoint..."

	# Create the private DNS zone group for the Azure Container Registry private endpoint
	az network private-endpoint dns-zone-group create \
		--name "$PRIVATE_DNS_ZONE_GROUP_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--endpoint-name "$PRIVATE_ENDPOINT_NAME" \
		--private-dns-zone "$PRIVATE_DNS_ZONE_NAME" \
		--zone-name "$PRIVATE_DNS_ZONE_NAME" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PRIVATE_ENDPOINT_NAME] private endpoint successfully created"
	else
		echo "Failed to create private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PRIVATE_ENDPOINT_NAME] private endpoint"
		exit
	fi
else
	echo "Private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PRIVATE_ENDPOINT_NAME] private endpoint already exists"
fi

# Check if the App Service Plan already exists
echo "Checking if [$APP_SERVICE_PLAN_NAME] App Service Plan already exists in the [$RESOURCE_GROUP_NAME] resource group..."
az appservice plan show \
	--name "$APP_SERVICE_PLAN_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APP_SERVICE_PLAN_NAME] App Service Plan exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating Linux App Service Plan [$APP_SERVICE_PLAN_NAME]..."
	az appservice plan create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$APP_SERVICE_PLAN_NAME" \
		--location "$LOCATION" \
		--sku "$APP_SERVICE_PLAN_SKU" \
		--is-linux \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "App Service Plan [$APP_SERVICE_PLAN_NAME] created successfully."
	else
		echo "Failed to create App Service Plan [$APP_SERVICE_PLAN_NAME]."
		exit 1
	fi
else
	echo "[$APP_SERVICE_PLAN_NAME] App Service Plan already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Get the App Service Plan resource id
echo "Getting [$APP_SERVICE_PLAN_NAME] App Service Plan resource id in the [$RESOURCE_GROUP_NAME] resource group..."
APP_SERVICE_PLAN_ID=$(az appservice plan show \
	--name "$APP_SERVICE_PLAN_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $APP_SERVICE_PLAN_ID ]]; then
	echo "[$APP_SERVICE_PLAN_NAME] App Service Plan resource id retrieved successfully: $APP_SERVICE_PLAN_ID"
else
	echo "Failed to retrieve [$APP_SERVICE_PLAN_NAME] App Service Plan resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Check if the Web App already exists
echo "Checking if [$WEB_APP_NAME] Web App already exists in the [$RESOURCE_GROUP_NAME] resource group..."
az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$WEB_APP_NAME] Web App exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating Web App [$WEB_APP_NAME] from custom image [$FULL_IMAGE]..."
	az webapp create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--plan "$APP_SERVICE_PLAN_NAME" \
		--name "$WEB_APP_NAME" \
		--assign-identity "${IDENTITY_ID}" \
		--container-image-name "$FULL_IMAGE" \
		--vnet "$VIRTUAL_NETWORK_NAME" \
		--subnet "$WEB_APP_SUBNET_NAME" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Web App [$WEB_APP_NAME] created successfully."
	else
		echo "Failed to create Web App [$WEB_APP_NAME]."
		exit 1
	fi
else
	echo "[$WEB_APP_NAME] Web App already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Configure the App Service to use managed identity for ACR authentication
echo "Configuring Web App [$WEB_APP_NAME] to use managed identity [$MANAGED_IDENTITY_NAME] to access Azure Container Registry [$ACR_NAME]..."
az webapp config set \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--generic-configurations "{\"acrUseManagedIdentityCreds\": true, \"acrUserManagedIdentityID\": \"$CLIENT_ID\"}" 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web App [$WEB_APP_NAME] configured to use managed identity [$MANAGED_IDENTITY_NAME] to access Azure Container Registry [$ACR_NAME] successfully."
else
	echo "Failed to configure Web App [$WEB_APP_NAME] to use managed identity [$MANAGED_IDENTITY_NAME] to access Azure Container Registry [$ACR_NAME]."
	exit 1
fi

# Get the Web App resource id
echo "Getting [$WEB_APP_NAME] Web App resource id in the [$RESOURCE_GROUP_NAME] resource group..."
WEB_APP_ID=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $WEB_APP_ID ]]; then
	echo "[$WEB_APP_NAME] Web App resource id retrieved successfully: $WEB_APP_ID"
else
	echo "Failed to retrieve [$WEB_APP_NAME] Web App resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Enabling forced tunneling for the web app to route all outbound traffic through the virtual network
echo "Enabling forced tunneling for web app [$WEB_APP_NAME] to route all outbound traffic through the virtual network..."

az resource update \
	--ids "$WEB_APP_ID" \
	--set properties.outboundVnetRouting.allTraffic=true \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Forced tunneling enabled for web app [$WEB_APP_NAME]."
else
	echo "Failed to enable forced tunneling for web app [$WEB_APP_NAME]."
	exit 1
fi

# Set web app settings
echo "Setting Web App container settings for [$WEB_APP_NAME]..."
az webapp config appsettings set \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--settings \
		WEBSITES_PORT="80" \
		APP_NAME="Custom Image" \
		IMAGE_NAME="$FULL_IMAGE" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web App settings for [$WEB_APP_NAME] set successfully."
else
	echo "Failed to set Web App settings for [$WEB_APP_NAME]."
	exit 1
fi

# Check if the Log Analytics workspace already exists
echo "Checking if [$LOG_ANALYTICS_NAME] Log Analytics workspace already exists in the [$RESOURCE_GROUP_NAME] resource group..."
az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$LOG_ANALYTICS_NAME] Log Analytics workspace actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$LOG_ANALYTICS_NAME] Log Analytics workspace in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the Log Analytics workspace
	az monitor log-analytics workspace create \
		--name "$LOG_ANALYTICS_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--query-access "Enabled" \
		--retention-time 30 \
		--sku "PerNode" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$LOG_ANALYTICS_NAME] Log Analytics workspace successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$LOG_ANALYTICS_NAME] Log Analytics workspace in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$LOG_ANALYTICS_NAME] Log Analytics workspace already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check whether the diagnostic settings for the container registry already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$ACR_NAME] container registry already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$ACR_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$ACR_NAME] container registry actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$ACR_NAME] container registry..."

	# Create the diagnostic settings for the container registry to send logs to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$ACR_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "ContainerRegistryRepositoryEvents", "enabled": true},
			{"category": "ContainerRegistryLoginEvents", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$ACR_NAME] container registry successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$ACR_NAME] container registry"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$ACR_NAME] container registry already exist"
fi

# Check whether the diagnostic settings for the web app already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$WEB_APP_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app..."

	# Create the diagnostic settings for the web app to send logs to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$WEB_APP_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "AppServiceHTTPLogs", "enabled": true},
			{"category": "AppServiceConsoleLogs", "enabled": true},
			{"category": "AppServiceAppLogs", "enabled": true},
			{"category": "AppServiceAuditLogs", "enabled": true},
			{"category": "AppServiceIPSecAuditLogs", "enabled": true},
			{"category": "AppServicePlatformLogs", "enabled": true},
			{"category": "AppServiceAuthenticationLogs", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app already exist"
fi

# Check whether the diagnostic settings for the App Service Plan already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service Plan already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$APP_SERVICE_PLAN_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service Plan actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service Plan..."

	# Create the diagnostic settings for the App Service Plan to send metrics to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$APP_SERVICE_PLAN_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service Plan successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service Plan"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service Plan already exist"
fi

# Check whether the diagnostic settings for the virtual network already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$VIRTUAL_NETWORK_NAME] virtual network already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$VIRTUAL_NETWORK_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$VIRTUAL_NETWORK_NAME] virtual network actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$VIRTUAL_NETWORK_NAME] virtual network..."

	# Create the diagnostic settings for the virtual network to send logs to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$VIRTUAL_NETWORK_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "VMProtectionAlerts", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$VIRTUAL_NETWORK_NAME] virtual network successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$VIRTUAL_NETWORK_NAME] virtual network"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$VIRTUAL_NETWORK_NAME] virtual network already exist"
fi

# Check whether the diagnostic settings for the network security group for the web app subnet already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$WEB_APP_SUBNET_NSG_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet..."

	# Create the diagnostic settings for the network security group for the web app subnet to send logs to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$WEB_APP_SUBNET_NSG_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "NetworkSecurityGroupEvent", "enabled": true},
			{"category": "NetworkSecurityGroupRuleCounter", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_SUBNET_NSG_NAME] network security group for the web app subnet already exist"
fi

# Check whether the diagnostic settings for the network security group for the private endpoint subnet already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$PE_SUBNET_NSG_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet..."

	# Create the diagnostic settings for the network security group for the private endpoint subnet to send logs to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$PE_SUBNET_NSG_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "NetworkSecurityGroupEvent", "enabled": true},
			{"category": "NetworkSecurityGroupRuleCounter", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PE_SUBNET_NSG_NAME] network security group for the private endpoint subnet already exist"
fi

echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table

echo ""
echo "Deployment complete."
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "App Service Plan: $APP_SERVICE_PLAN_NAME"
echo "Web App: $WEB_APP_NAME"
echo "Azure Container Registry: $ACR_NAME ($ACR_LOGIN_SERVER)"
echo "Image: $FULL_IMAGE"
echo "Managed Identity: $MANAGED_IDENTITY_NAME"
echo ""
echo "Run 'bash scripts/validate.sh' to verify the deployment."
