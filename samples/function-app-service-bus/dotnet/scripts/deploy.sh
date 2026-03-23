#!/bin/bash

PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
DIAGNOSTIC_SETTINGS_NAME='default'
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}"
FUNCTION_APP_SUBNET_NSG_NAME="${PREFIX}-func-subnet-nsg-${SUFFIX}"
PE_SUBNET_NSG_NAME="${PREFIX}-pe-subnet-nsg-${SUFFIX}"
NAT_GATEWAY_NAME="${PREFIX}-nat-gateway-${SUFFIX}"
PIP_PREFIX_NAME="${PREFIX}-nat-gateway-pip-prefix-${SUFFIX}"
VIRTUAL_NETWORK_NAME="${PREFIX}-vnet-${SUFFIX}"
VIRTUAL_NETWORK_ADDRESS_PREFIX="10.0.0.0/8"
FUNCTION_APP_SUBNET_NAME="func-subnet"
FUNCTION_APP_SUBNET_PREFIX="10.0.0.0/24"
PE_SUBNET_NAME="pe-subnet"
PE_SUBNET_PREFIX="10.0.1.0/24"
VIRTUAL_NETWORK_LINK_NAME="link-to-vnet"
PRIVATE_DNS_ZONE_GROUP_NAME="default"
APPLICATION_INSIGHTS_NAME="${PREFIX}-func-${SUFFIX}"
APP_SERVICE_PLAN_NAME="${PREFIX}-plan-${SUFFIX}"
FUNCTION_APP_NAME="${PREFIX}-func-${SUFFIX}"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
SERVICE_BUS_NAMESPACE="${PREFIX}-service-bus-${SUFFIX}"
FUNCTIONS_VERSION="4"
RUNTIME="DOTNET-ISOLATED"
RUNTIME_VERSION="10"
SERVICE_BUS_CONNECTION_STRING=''
INPUT_QUEUE_NAME="input"
OUTPUT_QUEUE_NAME="output"
TAGS='environment=test deployment=azcli'
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
DEPLOY=1
RETRY_COUNT=3
SLEEP=5
ZIPFILE="functionapp.zip"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRIVATE_DNS_ZONE_NAMES=(
	"privatelink.servicebus.windows.net"
	"privatelink.blob.core.windows.net"
	"privatelink.queue.core.windows.net"
	"privatelink.table.core.windows.net"
)
PE_NAMES=(
	"${PREFIX}-service-bus-pe-${SUFFIX}"
	"${PREFIX}-blob-storage-pe-${SUFFIX}"
	"${PREFIX}-queue-storage-pe-${SUFFIX}"
	"${PREFIX}-table-storage-pe-${SUFFIX}"
)
PE_GROUP_IDS=("namespace" "blob" "queue" "table")
PE_CONNECTION_NAMES=("servicebus-connection" "blob-connection" "queue-connection" "table-connection")
PE_DNS_ZONES=("privatelink.servicebus.windows.net" "privatelink.blob.core.windows.net" "privatelink.queue.core.windows.net" "privatelink.table.core.windows.net")
PE_DNS_ZONE_LABELS=("servicebus-zone" "blob-zone" "queue-zone" "table-zone")

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Create a resource group
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null
if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	# Create the resource group
	az group create \
		--name $RESOURCE_GROUP_NAME \
		--location $LOCATION \
		--tags $TAGS \
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

# Create a service bus namespace
echo "Checking if [$SERVICE_BUS_NAMESPACE] service bus namespace exists in the [$RESOURCE_GROUP_NAME] resource group..."
az servicebus namespace show \
	--name $SERVICE_BUS_NAMESPACE \
	--resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$SERVICE_BUS_NAMESPACE] service bus namespace exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$SERVICE_BUS_NAMESPACE] service bus namespace in the [$RESOURCE_GROUP_NAME] resource group..."
	az servicebus namespace create \
		--name $SERVICE_BUS_NAMESPACE \
		--sku Premium \
		--location $LOCATION \
		--resource-group $RESOURCE_GROUP_NAME \
		--tags $TAGS 1>/dev/null

	if [ $? == 0 ]; then
		echo "[$SERVICE_BUS_NAMESPACE] service bus namespace successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$SERVICE_BUS_NAMESPACE] service bus namespace in the [$RESOURCE_GROUP_NAME] resource group"
		exit
	fi
else
	echo "[$SERVICE_BUS_NAMESPACE] service bus namespace already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Create the service bus input queue
echo "Checking if [$INPUT_QUEUE_NAME] service bus queue exists in the [$SERVICE_BUS_NAMESPACE] service bus namespace..."
az servicebus queue show \
	--name $INPUT_QUEUE_NAME \
	--namespace-name $SERVICE_BUS_NAMESPACE \
	--resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$INPUT_QUEUE_NAME] service bus queue exists in the [$SERVICE_BUS_NAMESPACE] service bus namespace"
	echo "Creating [$INPUT_QUEUE_NAME] service bus queue in the [$SERVICE_BUS_NAMESPACE] service bus namespace..."

	az servicebus queue create \
		--name $INPUT_QUEUE_NAME \
		--namespace-name $SERVICE_BUS_NAMESPACE \
		--resource-group $RESOURCE_GROUP_NAME 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$INPUT_QUEUE_NAME] service bus queue successfully created in the [$SERVICE_BUS_NAMESPACE] service bus namespace"
	else
		echo "Failed to create [$INPUT_QUEUE_NAME] service bus queue in the [$SERVICE_BUS_NAMESPACE] service bus namespace"
		exit
	fi
else
	echo "[$INPUT_QUEUE_NAME] service bus queue already exists in the [$SERVICE_BUS_NAMESPACE] service bus namespace"
fi

# Create the service bus output queue
echo "Checking if [$OUTPUT_QUEUE_NAME] service bus queue exists in the [$SERVICE_BUS_NAMESPACE] service bus namespace..."
az servicebus queue show \
	--name $OUTPUT_QUEUE_NAME \
	--namespace-name $SERVICE_BUS_NAMESPACE \
	--resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$OUTPUT_QUEUE_NAME] service bus queue exists in the [$SERVICE_BUS_NAMESPACE] service bus namespace"
	echo "Creating [$OUTPUT_QUEUE_NAME] service bus queue in the [$SERVICE_BUS_NAMESPACE] service bus namespace..."

	az servicebus queue create \
		--name $OUTPUT_QUEUE_NAME \
		--namespace-name $SERVICE_BUS_NAMESPACE \
		--resource-group $RESOURCE_GROUP_NAME 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$OUTPUT_QUEUE_NAME] service bus queue successfully created in the [$SERVICE_BUS_NAMESPACE] service bus namespace"
	else
		echo "Failed to create [$OUTPUT_QUEUE_NAME] service bus queue in the [$SERVICE_BUS_NAMESPACE] service bus namespace"
		exit
	fi
else
	echo "[$OUTPUT_QUEUE_NAME] service bus queue already exists in the [$SERVICE_BUS_NAMESPACE] service bus namespace"
fi

# Retrieve and display connection string
SERVICE_BUS_CONNECTION_STRING=$(az servicebus namespace authorization-rule keys list \
	--name RootManageSharedAccessKey \
	--namespace-name $SERVICE_BUS_NAMESPACE \
	--resource-group $RESOURCE_GROUP_NAME \
	--query primaryConnectionString \
	--output tsv)

echo "Service Bus connection string: $SERVICE_BUS_CONNECTION_STRING"

# Get the Service Bus namespace resource id
echo "Getting [$SERVICE_BUS_NAMESPACE] service bus namespace resource id in the [$RESOURCE_GROUP_NAME] resource group..."
SERVICE_BUS_NAMESPACE_ID=$(az servicebus namespace show \
	--name $SERVICE_BUS_NAMESPACE \
	--resource-group $RESOURCE_GROUP_NAME \
	--query id \
	--output tsv)

if [[ -n $SERVICE_BUS_NAMESPACE_ID ]]; then
	echo "[$SERVICE_BUS_NAMESPACE] service bus namespace resource id retrieved successfully: $SERVICE_BUS_NAMESPACE_ID"
else
	echo "Failed to retrieve [$SERVICE_BUS_NAMESPACE] service bus namespace resource id in the [$RESOURCE_GROUP_NAME] resource group"
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
		--tags $TAGS 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$MANAGED_IDENTITY_NAME] user-assigned managed identity successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$MANAGED_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$MANAGED_IDENTITY_NAME] user-assigned managed identity already exists in the [$RESOURCE_GROUP_NAME] resource group"
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

# Check if the network security group for the function app subnet already exists
echo "Checking if [$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az network nsg show \
	--name "$FUNCTION_APP_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet..."

	# Create the network security group for the function app subnet
	az network nsg create \
		--name "$FUNCTION_APP_SUBNET_NSG_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--tags $TAGS \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Get the resource id of the network security group for the function app subnet
echo "Getting [$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet resource id in the [$RESOURCE_GROUP_NAME] resource group..."
FUNCTION_APP_SUBNET_NSG_ID=$(az network nsg show \
	--name "$FUNCTION_APP_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $FUNCTION_APP_SUBNET_NSG_ID ]]; then
	echo "[$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet resource id retrieved successfully: $FUNCTION_APP_SUBNET_NSG_ID"
else
	echo "Failed to retrieve [$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet resource id in the [$RESOURCE_GROUP_NAME] resource group"
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
		--tags $TAGS \
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
		--tags $TAGS \
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
		--tags $TAGS \
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
		--subnet-name "$FUNCTION_APP_SUBNET_NAME" \
		--subnet-prefix "$FUNCTION_APP_SUBNET_PREFIX" \
		--tags $TAGS \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$VIRTUAL_NETWORK_NAME] virtual network successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$VIRTUAL_NETWORK_NAME] virtual network in the [$RESOURCE_GROUP_NAME] resource group"
		exit
	fi

	# Update the function app subnet to associate it with the NAT Gateway and the NSG
	echo "Associating [$FUNCTION_APP_SUBNET_NAME] subnet with the [$NAT_GATEWAY_NAME] NAT Gateway and the [$FUNCTION_APP_SUBNET_NSG_NAME] network security group..."

	# Update the function app subnet to associate it with the NAT Gateway and the NSG
	az network vnet subnet update \
		--name "$FUNCTION_APP_SUBNET_NAME" \
		--vnet-name "$VIRTUAL_NETWORK_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--nat-gateway "$NAT_GATEWAY_NAME" \
		--network-security-group "$FUNCTION_APP_SUBNET_NSG_NAME" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$FUNCTION_APP_SUBNET_NAME] subnet successfully associated with the [$NAT_GATEWAY_NAME] NAT Gateway and the [$FUNCTION_APP_SUBNET_NSG_NAME] network security group"
	else
		echo "Failed to associate [$FUNCTION_APP_SUBNET_NAME] subnet with the [$NAT_GATEWAY_NAME] NAT Gateway and the [$FUNCTION_APP_SUBNET_NSG_NAME] network security group"
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
	--only-show-errors \
	--query id \
	--output tsv)

if [[ -n $VIRTUAL_NETWORK_ID ]]; then
	echo "[$VIRTUAL_NETWORK_NAME] virtual network resource id retrieved successfully: $VIRTUAL_NETWORK_ID"
else
	echo "Failed to retrieve [$VIRTUAL_NETWORK_NAME] virtual network resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit
fi

# Create private DNS zones and virtual network links
for DNS_ZONE_NAME in "${PRIVATE_DNS_ZONE_NAMES[@]}"; do
	# Check if the private DNS Zone already exists
	echo "Checking if [$DNS_ZONE_NAME] private DNS zone actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
	az network private-dns zone show \
		--name "$DNS_ZONE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--only-show-errors &>/dev/null

	if [[ $? != 0 ]]; then
		echo "No [$DNS_ZONE_NAME] private DNS zone actually exists in the [$RESOURCE_GROUP_NAME] resource group"
		echo "Creating [$DNS_ZONE_NAME] private DNS zone in the [$RESOURCE_GROUP_NAME] resource group..."

		# Create the private DNS Zone
		az network private-dns zone create \
			--name "$DNS_ZONE_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--tags $TAGS \
			--only-show-errors 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "[$DNS_ZONE_NAME] private DNS zone successfully created in the [$RESOURCE_GROUP_NAME] resource group"
		else
			echo "Failed to create [$DNS_ZONE_NAME] private DNS zone in the [$RESOURCE_GROUP_NAME] resource group"
			exit
		fi
	else
		echo "[$DNS_ZONE_NAME] private DNS zone already exists in the [$RESOURCE_GROUP_NAME] resource group"
	fi

	# Check if the virtual network link already exists
	echo "Checking if [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network actually exists..."
	az network private-dns link vnet show \
		--name "$VIRTUAL_NETWORK_LINK_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--zone-name "$DNS_ZONE_NAME" \
		--only-show-errors &>/dev/null

	if [[ $? != 0 ]]; then
		echo "No [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network actually exists"
		echo "Creating [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network..."

		# Create the virtual network link
		az network private-dns link vnet create \
			--name "$VIRTUAL_NETWORK_LINK_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--zone-name "$DNS_ZONE_NAME" \
			--virtual-network "$VIRTUAL_NETWORK_ID" \
			--registration-enabled false \
			--only-show-errors 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "[$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network successfully created"
		else
			echo "Failed to create [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network"
			exit
		fi
	else
		echo "[$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$DNS_ZONE_NAME] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network already exists"
	fi
done

# Create a storage account
echo "Checking if storage account [$STORAGE_ACCOUNT_NAME] exists in the resource group [$RESOURCE_GROUP_NAME]..."
az storage account show \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No storage account [$STORAGE_ACCOUNT_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group."
	echo "Creating storage account [$STORAGE_ACCOUNT_NAME] in the [$RESOURCE_GROUP_NAME] resource group..."
	az storage account create \
		--name $STORAGE_ACCOUNT_NAME \
		--location $LOCATION \
		--resource-group $RESOURCE_GROUP_NAME \
		--sku Standard_LRS \
		--tags $TAGS \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Storage account [$STORAGE_ACCOUNT_NAME] created successfully in the [$RESOURCE_GROUP_NAME] resource group."
	else
		echo "Failed to create storage account [$STORAGE_ACCOUNT_NAME] in the [$RESOURCE_GROUP_NAME] resource group."
		exit 1
	fi
else
	echo "Storage account [$STORAGE_ACCOUNT_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group."
fi

# Get the storage account key
echo "Getting storage account key for [$STORAGE_ACCOUNT_NAME]..."
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
	--account-name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "[0].value" \
	--output tsv)

if [ -n "$STORAGE_ACCOUNT_KEY" ]; then
	echo "Storage account key retrieved successfully: [$STORAGE_ACCOUNT_KEY]"
else
	echo "Failed to retrieve storage account key."
	exit 1
fi

# Construct the storage connection string for LocalStack
STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT_NAME;AccountKey=$STORAGE_ACCOUNT_KEY;EndpointSuffix=core.windows.net"
echo "Storage connection string constructed: [$STORAGE_CONNECTION_STRING]"

# Get the storage account resource id
echo "Getting [$STORAGE_ACCOUNT_NAME] storage account resource id in the [$RESOURCE_GROUP_NAME] resource group..."
STORAGE_ACCOUNT_ID=$(az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $STORAGE_ACCOUNT_ID ]]; then
	echo "[$STORAGE_ACCOUNT_NAME] storage account resource id retrieved successfully: $STORAGE_ACCOUNT_ID"
else
	echo "Failed to retrieve [$STORAGE_ACCOUNT_NAME] storage account resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Create private endpoints and DNS zone groups
PE_RESOURCE_IDS=("$SERVICE_BUS_NAMESPACE_ID" "$STORAGE_ACCOUNT_ID" "$STORAGE_ACCOUNT_ID" "$STORAGE_ACCOUNT_ID")

for i in "${!PE_NAMES[@]}"; do
	PE_NAME="${PE_NAMES[$i]}"
	PE_GROUP="${PE_GROUP_IDS[$i]}"
	PE_RESOURCE_ID="${PE_RESOURCE_IDS[$i]}"
	PE_CONNECTION="${PE_CONNECTION_NAMES[$i]}"
	PE_DNS_ZONE="${PE_DNS_ZONES[$i]}"
	PE_DNS_ZONE_LABEL="${PE_DNS_ZONE_LABELS[$i]}"

	# Check if the private endpoint already exists
	echo "Checking if private endpoint [$PE_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group..."
	privateEndpointId=$(az network private-endpoint list \
		--resource-group $RESOURCE_GROUP_NAME \
		--only-show-errors \
		--query "[?name=='$PE_NAME'].id" \
		--output tsv)

	if [[ -z $privateEndpointId ]]; then
		echo "Private endpoint [$PE_NAME] does not exist in the [$RESOURCE_GROUP_NAME] resource group"
		echo "Creating [$PE_NAME] private endpoint in the [$RESOURCE_GROUP_NAME] resource group..."

		# Create the private endpoint
		az network private-endpoint create \
			--name "$PE_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--location "$LOCATION" \
			--vnet-name "$VIRTUAL_NETWORK_NAME" \
			--subnet "$PE_SUBNET_NAME" \
			--private-connection-resource-id "$PE_RESOURCE_ID" \
			--group-id "$PE_GROUP" \
			--connection-name "$PE_CONNECTION" \
			--tags $TAGS \
			--only-show-errors 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "Private endpoint [$PE_NAME] successfully created in the [$RESOURCE_GROUP_NAME] resource group"
		else
			echo "Failed to create private endpoint [$PE_NAME] in the [$RESOURCE_GROUP_NAME] resource group"
			exit
		fi
	else
		echo "Private endpoint [$PE_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group"
	fi

	# Check if the private DNS zone group is already created
	echo "Checking if the private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PE_NAME] private endpoint already exists..."
	az network private-endpoint dns-zone-group show \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--endpoint-name "$PE_NAME" \
		--name "$PRIVATE_DNS_ZONE_GROUP_NAME" \
		--query name \
		--output tsv \
		--only-show-errors &>/dev/null

	if [[ $? != 0 ]]; then
		echo "No private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PE_NAME] private endpoint actually exists"
		echo "Creating private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PE_NAME] private endpoint..."

		# Create the private DNS zone group
		az network private-endpoint dns-zone-group create \
			--name "$PRIVATE_DNS_ZONE_GROUP_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--endpoint-name "$PE_NAME" \
			--private-dns-zone "$PE_DNS_ZONE" \
			--zone-name "$PE_DNS_ZONE_LABEL" \
			--only-show-errors 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "Private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PE_NAME] private endpoint successfully created"
		else
			echo "Failed to create private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PE_NAME] private endpoint"
			exit
		fi
	else
		echo "Private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$PE_NAME] private endpoint already exists"
	fi
done

if [ $DEPLOY -eq 0 ]; then
	echo "Deployment flag is not set. Exiting deployment script."
	exit 0
fi

# Check if the application insights component already exists
echo "Checking if [$APPLICATION_INSIGHTS_NAME] Application Insights component exists in the [$RESOURCE_GROUP_NAME] resource group..."
az monitor app-insights component show \
	--app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APPLICATION_INSIGHTS_NAME] Application Insights component exists in the [$RESOURCE_GROUP_NAME] resource group."
	echo "Creating [$APPLICATION_INSIGHTS_NAME] Application Insights component in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the application insights component
	az monitor app-insights component create \
		--app "$APPLICATION_INSIGHTS_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--application-type "web" \
		--tags $TAGS \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$APPLICATION_INSIGHTS_NAME] Application Insights component created successfully in the [$RESOURCE_GROUP_NAME] resource group."
	else
		echo "Failed to create [$APPLICATION_INSIGHTS_NAME] Application Insights component in the [$RESOURCE_GROUP_NAME] resource group."
		exit 1
	fi
else
	echo "[$APPLICATION_INSIGHTS_NAME] Application Insights component already exists in the [$RESOURCE_GROUP_NAME] resource group."
fi

# Get the application insights component resource id
echo "Getting [$APPLICATION_INSIGHTS_NAME] Application Insights component resource id in the [$RESOURCE_GROUP_NAME] resource group..."
APPLICATION_INSIGHTS_ID=$(az monitor app-insights component show \
	--app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $APPLICATION_INSIGHTS_ID ]]; then
	echo "[$APPLICATION_INSIGHTS_NAME] Application Insights component resource id retrieved successfully: $APPLICATION_INSIGHTS_ID"
else
	echo "Failed to retrieve [$APPLICATION_INSIGHTS_NAME] Application Insights component resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Assign the Azure Service Bus Data Owner role to the managed identity with the Service Bus namespace as a scope
ROLE="Azure Service Bus Data Owner"
echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity has the [$ROLE] role assignment on the Service Bus namespace [$SERVICE_BUS_NAMESPACE]..."
current=$(az role assignment list \
	--assignee "$PRINCIPAL_ID" \
	--scope "$SERVICE_BUS_NAMESPACE_ID" \
	--query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == "$ROLE" ]]; then
	echo "[$MANAGED_IDENTITY_NAME] managed identity already has the [$ROLE] role assignment on the Service Bus namespace [$SERVICE_BUS_NAMESPACE]"
else
	echo "[$MANAGED_IDENTITY_NAME] managed identity does not have the [$ROLE] role assignment on the Service Bus namespace [$SERVICE_BUS_NAMESPACE]"
	echo "Creating role assignment: assigning [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the Service Bus namespace [$SERVICE_BUS_NAMESPACE]..."
	ATTEMPT=1
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		az role assignment create \
			--assignee "$PRINCIPAL_ID" \
			--role "$ROLE" \
			--scope "$SERVICE_BUS_NAMESPACE_ID" \
			--only-show-errors 1>/dev/null

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
		echo "Successfully assigned [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the Service Bus namespace [$SERVICE_BUS_NAMESPACE]"
	else
		echo "Failed to assign [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the Service Bus namespace [$SERVICE_BUS_NAMESPACE]"
		exit
	fi
fi

# Get the storage account resource id for role assignments
echo "Getting [$STORAGE_ACCOUNT_NAME] storage account resource id in the [$RESOURCE_GROUP_NAME] resource group..."
STORAGE_ACCOUNT_ID=$(az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $STORAGE_ACCOUNT_ID ]]; then
	echo "[$STORAGE_ACCOUNT_NAME] storage account resource id retrieved successfully"
else
	echo "Failed to retrieve [$STORAGE_ACCOUNT_NAME] storage account resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Assign the Storage Account Contributor role to the managed identity with the storage account as a scope
ROLE="Storage Account Contributor"
echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity has the [$ROLE] role assignment on the storage account [$STORAGE_ACCOUNT_NAME]..."
current=$(az role assignment list \
	--assignee "$PRINCIPAL_ID" \
	--scope "$STORAGE_ACCOUNT_ID" \
	--query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == "$ROLE" ]]; then
	echo "[$MANAGED_IDENTITY_NAME] managed identity already has the [$ROLE] role assignment on the storage account [$STORAGE_ACCOUNT_NAME]"
else
	echo "[$MANAGED_IDENTITY_NAME] managed identity does not have the [$ROLE] role assignment on the storage account [$STORAGE_ACCOUNT_NAME]"
	echo "Creating role assignment: assigning [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the storage account [$STORAGE_ACCOUNT_NAME]..."
	ATTEMPT=1
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		az role assignment create \
			--assignee "$PRINCIPAL_ID" \
			--role "$ROLE" \
			--scope "$STORAGE_ACCOUNT_ID" \
			--only-show-errors 1>/dev/null

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
		echo "Successfully assigned [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the storage account [$STORAGE_ACCOUNT_NAME]"
	else
		echo "Failed to assign [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the storage account [$STORAGE_ACCOUNT_NAME]"
		exit
	fi
fi

# Assign the Storage Blob Data Owner role to the managed identity with the storage account as a scope
ROLE="Storage Blob Data Owner"
echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity has the [$ROLE] role assignment on the storage account [$STORAGE_ACCOUNT_NAME]..."
current=$(az role assignment list \
	--assignee "$PRINCIPAL_ID" \
	--scope "$STORAGE_ACCOUNT_ID" \
	--query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == "$ROLE" ]]; then
	echo "[$MANAGED_IDENTITY_NAME] managed identity already has the [$ROLE] role assignment on the storage account [$STORAGE_ACCOUNT_NAME]"
else
	echo "[$MANAGED_IDENTITY_NAME] managed identity does not have the [$ROLE] role assignment on the storage account [$STORAGE_ACCOUNT_NAME]"
	echo "Creating role assignment: assigning [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the storage account [$STORAGE_ACCOUNT_NAME]..."
	ATTEMPT=1
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		az role assignment create \
			--assignee "$PRINCIPAL_ID" \
			--role "$ROLE" \
			--scope "$STORAGE_ACCOUNT_ID" \
			--only-show-errors 1>/dev/null

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
		echo "Successfully assigned [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the storage account [$STORAGE_ACCOUNT_NAME]"
	else
		echo "Failed to assign [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the storage account [$STORAGE_ACCOUNT_NAME]"
		exit
	fi
fi

# Assign the Storage Queue Data Contributor role to the managed identity with the storage account as a scope
ROLE="Storage Queue Data Contributor"
echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity has the [$ROLE] role assignment on the storage account [$STORAGE_ACCOUNT_NAME]..."
current=$(az role assignment list \
	--assignee "$PRINCIPAL_ID" \
	--scope "$STORAGE_ACCOUNT_ID" \
	--query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == "$ROLE" ]]; then
	echo "[$MANAGED_IDENTITY_NAME] managed identity already has the [$ROLE] role assignment on the storage account [$STORAGE_ACCOUNT_NAME]"
else
	echo "[$MANAGED_IDENTITY_NAME] managed identity does not have the [$ROLE] role assignment on the storage account [$STORAGE_ACCOUNT_NAME]"
	echo "Creating role assignment: assigning [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the storage account [$STORAGE_ACCOUNT_NAME]..."
	ATTEMPT=1
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		az role assignment create \
			--assignee "$PRINCIPAL_ID" \
			--role "$ROLE" \
			--scope "$STORAGE_ACCOUNT_ID" \
			--only-show-errors 1>/dev/null

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
		echo "Successfully assigned [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the storage account [$STORAGE_ACCOUNT_NAME]"
	else
		echo "Failed to assign [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the storage account [$STORAGE_ACCOUNT_NAME]"
		exit
	fi
fi

# Assign the Storage Table Data Contributor role to the managed identity with the storage account as a scope
ROLE="Storage Table Data Contributor"
echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity has the [$ROLE] role assignment on the storage account [$STORAGE_ACCOUNT_NAME]..."
current=$(az role assignment list \
	--assignee "$PRINCIPAL_ID" \
	--scope "$STORAGE_ACCOUNT_ID" \
	--query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == "$ROLE" ]]; then
	echo "[$MANAGED_IDENTITY_NAME] managed identity already has the [$ROLE] role assignment on the storage account [$STORAGE_ACCOUNT_NAME]"
else
	echo "[$MANAGED_IDENTITY_NAME] managed identity does not have the [$ROLE] role assignment on the storage account [$STORAGE_ACCOUNT_NAME]"
	echo "Creating role assignment: assigning [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the storage account [$STORAGE_ACCOUNT_NAME]..."
	ATTEMPT=1
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		az role assignment create \
			--assignee "$PRINCIPAL_ID" \
			--role "$ROLE" \
			--scope "$STORAGE_ACCOUNT_ID" \
			--only-show-errors 1>/dev/null

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
		echo "Successfully assigned [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the storage account [$STORAGE_ACCOUNT_NAME]"
	else
		echo "Failed to assign [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the storage account [$STORAGE_ACCOUNT_NAME]"
		exit
	fi
fi

# Assign the Monitoring Metrics Publisher role to the managed identity with the Application Insights as a scope
ROLE="Monitoring Metrics Publisher"
echo "Checking if the [$MANAGED_IDENTITY_NAME] managed identity has the [$ROLE] role assignment on the Application Insights [$APPLICATION_INSIGHTS_NAME]..."
current=$(az role assignment list \
	--assignee "$PRINCIPAL_ID" \
	--scope "$APPLICATION_INSIGHTS_ID" \
	--query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == "$ROLE" ]]; then
	echo "[$MANAGED_IDENTITY_NAME] managed identity already has the [$ROLE] role assignment on the Application Insights [$APPLICATION_INSIGHTS_NAME]"
else
	echo "[$MANAGED_IDENTITY_NAME] managed identity does not have the [$ROLE] role assignment on the Application Insights [$APPLICATION_INSIGHTS_NAME]"
	echo "Creating role assignment: assigning [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the Application Insights [$APPLICATION_INSIGHTS_NAME]..."
	ATTEMPT=1
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		az role assignment create \
			--assignee "$PRINCIPAL_ID" \
			--role "$ROLE" \
			--scope "$APPLICATION_INSIGHTS_ID" \
			--only-show-errors 1>/dev/null

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
		echo "Successfully assigned [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the Application Insights [$APPLICATION_INSIGHTS_NAME]"
	else
		echo "Failed to assign [$ROLE] role to [$MANAGED_IDENTITY_NAME] managed identity on the Application Insights [$APPLICATION_INSIGHTS_NAME]"
		exit
	fi
fi

# Create the app service plan
echo "Checking if app service plan [$APP_SERVICE_PLAN_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group..."
if ! az appservice plan show \
	--name $APP_SERVICE_PLAN_NAME \
	--resource-group $RESOURCE_GROUP_NAME &>/dev/null; then
	echo "No app service plan [$APP_SERVICE_PLAN_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group."
	echo "Creating app service plan [$APP_SERVICE_PLAN_NAME] in the [$RESOURCE_GROUP_NAME] resource group..."
	if az appservice plan create \
		--name $APP_SERVICE_PLAN_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location $LOCATION \
		--sku B1 \
		--is-linux \
		--tags $TAGS \
		--only-show-errors 1>/dev/null; then
		echo "App service plan [$APP_SERVICE_PLAN_NAME] created successfully in the [$RESOURCE_GROUP_NAME] resource group."
	else
		echo "Failed to create app service plan [$APP_SERVICE_PLAN_NAME] in the [$RESOURCE_GROUP_NAME] resource group."
		exit 1
	fi
else
	echo "App service plan [$APP_SERVICE_PLAN_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group."
fi

# Get the app service plan resource id
echo "Getting [$APP_SERVICE_PLAN_NAME] app service plan resource id in the [$RESOURCE_GROUP_NAME] resource group..."
APP_SERVICE_PLAN_ID=$(az appservice plan show \
	--name "$APP_SERVICE_PLAN_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $APP_SERVICE_PLAN_ID ]]; then
	echo "[$APP_SERVICE_PLAN_NAME] app service plan resource id retrieved successfully: $APP_SERVICE_PLAN_ID"
else
	echo "Failed to retrieve [$APP_SERVICE_PLAN_NAME] app service plan resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Check if the function app already exists
echo "Checking if function app [$FUNCTION_APP_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group..."
if ! az functionapp show \
	--name $FUNCTION_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME &>/dev/null; then
	echo "No function app [$FUNCTION_APP_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group."
	echo "Creating function app [$FUNCTION_APP_NAME] in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the function app
	az functionapp create \
		--resource-group $RESOURCE_GROUP_NAME \
		--plan $APP_SERVICE_PLAN_NAME \
		--assign-identity "$IDENTITY_ID" \
		--runtime $RUNTIME \
		--runtime-version $RUNTIME_VERSION \
		--functions-version $FUNCTIONS_VERSION \
		--name $FUNCTION_APP_NAME \
		--os-type linux \
		--app-insights "$APPLICATION_INSIGHTS_NAME" \
		--storage-account $STORAGE_ACCOUNT_NAME \
		--vnet "$VIRTUAL_NETWORK_NAME" \
		--subnet "$FUNCTION_APP_SUBNET_NAME" \
		--tags $TAGS \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Function app [$FUNCTION_APP_NAME] created successfully."
	else
		echo "Failed to create function app [$FUNCTION_APP_NAME]."
		exit 1
	fi
else
	echo "Function app [$FUNCTION_APP_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group."
fi

# Get the function app resource id
echo "Getting [$FUNCTION_APP_NAME] function app resource id in the [$RESOURCE_GROUP_NAME] resource group..."
FUNCTION_APP_ID=$(az functionapp show \
	--name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $FUNCTION_APP_ID ]]; then
	echo "[$FUNCTION_APP_NAME] function app resource id retrieved successfully: $FUNCTION_APP_ID"
else
	echo "Failed to retrieve [$FUNCTION_APP_NAME] function app resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Enable forced tunneling for the function app to route all outbound traffic through the virtual network and thus through the NAT Gateway
echo "Enabling forced tunneling for function app [$FUNCTION_APP_NAME] to route all outbound traffic through the virtual network..."

az resource update \
	--ids "$FUNCTION_APP_ID" \
	--set properties.outboundVnetRouting.allTraffic=true \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Forced tunneling enabled for function app [$FUNCTION_APP_NAME]."
else
	echo "Failed to enable forced tunneling for function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Set function app settings
echo "Setting function app settings for [$FUNCTION_APP_NAME]..."
az functionapp config appsettings set \
	--name $FUNCTION_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	AZURE_CLIENT_ID="$CLIENT_ID" \
	SCM_DO_BUILD_DURING_DEPLOYMENT=false \
	FUNCTIONS_WORKER_RUNTIME=${RUNTIME,,} \
	FUNCTIONS_EXTENSION_VERSION=~$FUNCTIONS_VERSION \
	AzureWebJobsStorage="$STORAGE_CONNECTION_STRING" \
	SERVICE_BUS_CONNECTION_STRING__fullyQualifiedNamespace="${SERVICE_BUS_NAMESPACE,,}.servicebus.windows.net" \
	INPUT_QUEUE_NAME="input" \
	OUTPUT_QUEUE_NAME="output" \
	NAMES="Paolo,John,Jane,Max,Mary,Leo,Mia,Anna,Lisa,Anastasia" \
	TIMER_SCHEDULE="*/10 * * * * *" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Function app settings for [$FUNCTION_APP_NAME] set successfully."
else
	echo "Failed to set function app settings for [$FUNCTION_APP_NAME]."
	exit 1
fi

# Check if the log analytics workspace already exists
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
		--tags $TAGS \
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

# Check whether the diagnostic settings for the function app already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_NAME] function app already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$FUNCTION_APP_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_NAME] function app actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_NAME] function app..."

	# Create the diagnostic settings for the function app to send logs to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$FUNCTION_APP_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "FunctionAppLogs", "enabled": true},
			{"category": "AppServiceAuthenticationLogs", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_NAME] function app successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_NAME] function app"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_NAME] function app already exist"
fi

# Check whether the diagnostic settings for the app service plan already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] app service plan already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$APP_SERVICE_PLAN_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] app service plan actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] app service plan..."

	# Create the diagnostic settings for the app service plan to send logs to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$APP_SERVICE_PLAN_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] app service plan successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] app service plan"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] app service plan already exist"
fi

# Check whether the diagnostic settings for the service bus namespace already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SERVICE_BUS_NAMESPACE] service bus namespace already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$SERVICE_BUS_NAMESPACE_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SERVICE_BUS_NAMESPACE] service bus namespace actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SERVICE_BUS_NAMESPACE] service bus namespace..."

	# Create the diagnostic settings for the service bus namespace to send logs to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$SERVICE_BUS_NAMESPACE_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "ApplicationMetricsLogs", "enabled": true},
			{"category": "DiagnosticErrorLogs", "enabled": true},
			{"category": "OperationalLogs", "enabled": true},
			{"category": "RuntimeAuditLogs", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SERVICE_BUS_NAMESPACE] service bus namespace successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SERVICE_BUS_NAMESPACE] service bus namespace"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SERVICE_BUS_NAMESPACE] service bus namespace already exist"
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

# Check whether the diagnostic settings for the network security group for the function app subnet already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$FUNCTION_APP_SUBNET_NSG_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet..."

	# Create the diagnostic settings for the network security group for the function app subnet to send logs to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$FUNCTION_APP_SUBNET_NSG_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "NetworkSecurityGroupEvent", "enabled": true},
			{"category": "NetworkSecurityGroupRuleCounter", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_SUBNET_NSG_NAME] network security group for the function app subnet already exist"
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

# CD into the function app directory
cd ../src || exit

# Remove any existing zip package of the function app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Build and publish the function app
echo "Building function app [$FUNCTION_APP_NAME]..."
if dotnet publish -c Release -o ./publish; then
	echo "Function app [$FUNCTION_APP_NAME] built successfully."
else
	echo "Failed to build function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Create the zip package of the publish output
echo "Creating zip package of the function app..."
cd ./publish || exit
zip -r "../$ZIPFILE" .
cd ..

# Deploy the function app
echo "Deploying function app [$FUNCTION_APP_NAME] with zip file [$ZIPFILE]..."
if az functionapp deployment source config-zip \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--src "$ZIPFILE" \
	--only-show-errors 1>/dev/null; then
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully."
else
	echo "Failed to deploy function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Remove the zip package of the function app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Print the list of resources in the resource group
echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table 