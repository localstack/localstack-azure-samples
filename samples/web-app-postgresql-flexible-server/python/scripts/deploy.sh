#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
DIAGNOSTIC_SETTINGS_NAME='default'
WEB_APP_SUBNET_NSG_NAME="${PREFIX}-webapp-subnet-nsg-${SUFFIX}"
PE_SUBNET_NSG_NAME="${PREFIX}-pe-subnet-nsg-${SUFFIX}"
NAT_GATEWAY_NAME="${PREFIX}-nat-gateway-${SUFFIX}"
PIP_PREFIX_NAME="${PREFIX}-nat-gateway-pip-prefix-${SUFFIX}"
VIRTUAL_NETWORK_NAME="${PREFIX}-vnet-${SUFFIX}"
VIRTUAL_NETWORK_ADDRESS_PREFIX="10.0.0.0/8"
WEB_APP_SUBNET_NAME="app-subnet"
WEB_APP_SUBNET_PREFIX="10.0.0.0/24"
PE_SUBNET_NAME="pe-subnet"
PE_SUBNET_PREFIX="10.0.1.0/24"
VIRTUAL_NETWORK_LINK_NAME="link-to-vnet"
PRIVATE_DNS_ZONE_NAME="privatelink.postgres.database.azure.com"
PRIVATE_ENDPOINT_NAME="${PREFIX}-postgres-pe-${SUFFIX}"
PRIVATE_ENDPOINT_GROUP="postgresqlServer"
PRIVATE_DNS_ZONE_GROUP_NAME="default"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="S1"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
POSTGRES_SERVER_NAME="${PREFIX}-pgflex-${SUFFIX}"
POSTGRES_VERSION="16"
POSTGRES_SKU_NAME="Standard_B1ms"
POSTGRES_SKU_TIER="Burstable"
POSTGRES_STORAGE_SIZE_GB=32
POSTGRES_BACKUP_RETENTION_DAYS=7
POSTGRES_DATABASE_NAME="PlannerDB"
PG_ADMIN_USER="pgadmin"
PG_ADMIN_PASSWORD="P@ssw0rd1234!"
PG_APP_USER="testuser"
PG_APP_PASSWORD="TestP@ssw0rd123"
FIREWALL_RULE_NAME="AllowAllIPs"
RUNTIME="python"
RUNTIME_VERSION="3.13"
LOGIN_NAME="paolo"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit
# Create a resource group
echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
az group create \
	--name $RESOURCE_GROUP_NAME \
	--location $LOCATION \
	--tags environment=test iac=az-cli \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Resource group [$RESOURCE_GROUP_NAME] created successfully."
else
	echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
	exit 1
fi

# Check if the PostgreSQL flexible server already exists
echo "Checking if [$POSTGRES_SERVER_NAME] PostgreSQL flexible server already exists in the [$RESOURCE_GROUP_NAME] resource group..."
az postgres flexible-server show \
	--name $POSTGRES_SERVER_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$POSTGRES_SERVER_NAME] PostgreSQL flexible server already exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$POSTGRES_SERVER_NAME] PostgreSQL flexible server in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create a PostgreSQL flexible server with public network access
	az postgres flexible-server create \
		--name $POSTGRES_SERVER_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location $LOCATION \
		--tier $POSTGRES_SKU_TIER \
		--sku-name $POSTGRES_SKU_NAME \
		--version $POSTGRES_VERSION \
		--storage-size $POSTGRES_STORAGE_SIZE_GB \
		--backup-retention $POSTGRES_BACKUP_RETENTION_DAYS \
		--geo-redundant-backup Disabled \
		--admin-user $PG_ADMIN_USER \
		--admin-password "$PG_ADMIN_PASSWORD" \
		--public-access Enabled \
		--high-availability Disabled \
		--yes \
		--tags environment=test iac=az-cli \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "[$POSTGRES_SERVER_NAME] PostgreSQL flexible server successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$POSTGRES_SERVER_NAME] PostgreSQL flexible server in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$POSTGRES_SERVER_NAME] PostgreSQL flexible server already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Retrieve the resource id of the PostgreSQL flexible server
echo "Getting [$POSTGRES_SERVER_NAME] PostgreSQL flexible server resource id in the [$RESOURCE_GROUP_NAME] resource group..."
POSTGRES_SERVER_ID=$(az postgres flexible-server show \
	--name $POSTGRES_SERVER_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query id \
	--output tsv \
	--only-show-errors)

if [ -n "$POSTGRES_SERVER_ID" ]; then
	echo "PostgreSQL flexible server resource id retrieved successfully: $POSTGRES_SERVER_ID"
else
	echo "Failed to retrieve PostgreSQL flexible server resource id."
	exit 1
fi

# Retrieve the fullyQualifiedDomainName of the PostgreSQL flexible server
echo "Getting [$POSTGRES_SERVER_NAME] PostgreSQL flexible server FQDN in the [$RESOURCE_GROUP_NAME] resource group..."
POSTGRES_FQDN_FULL=$(az postgres flexible-server show \
	--name $POSTGRES_SERVER_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "fullyQualifiedDomainName" \
	--output tsv \
	--only-show-errors)

if [ -n "$POSTGRES_FQDN_FULL" ]; then
	echo "PostgreSQL flexible server FQDN retrieved successfully: $POSTGRES_FQDN_FULL"
else
	echo "Failed to retrieve PostgreSQL flexible server FQDN."
	exit 1
fi

# Split host:port — the LocalStack emulator embeds the dynamically allocated TCP-proxy port
# directly in fullyQualifiedDomainName, mirroring the storage / container registry emulators.
# Real Azure returns just the bare host so PG_PORT defaults to 5432.
POSTGRES_FQDN="${POSTGRES_FQDN_FULL%%:*}"
if [[ "$POSTGRES_FQDN_FULL" == *:* ]]; then
	POSTGRES_PORT="${POSTGRES_FQDN_FULL##*:}"
else
	POSTGRES_PORT=5432
fi
echo "PostgreSQL host = $POSTGRES_FQDN, port = $POSTGRES_PORT"

# Check if the server-level firewall rule already exists
echo "Checking if [$FIREWALL_RULE_NAME] firewall rule already exists on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."
az postgres flexible-server firewall-rule show \
	--name $POSTGRES_SERVER_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--rule-name $FIREWALL_RULE_NAME \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$FIREWALL_RULE_NAME] firewall rule already exists on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
	echo "Creating [$FIREWALL_RULE_NAME] firewall rule on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."

	# Create a permissive firewall rule so the deploy machine can run the psql bootstrap
	az postgres flexible-server firewall-rule create \
		--name $POSTGRES_SERVER_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--rule-name $FIREWALL_RULE_NAME \
		--start-ip-address "0.0.0.0" \
		--end-ip-address "255.255.255.255" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "[$FIREWALL_RULE_NAME] firewall rule successfully created on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
	else
		echo "Failed to create [$FIREWALL_RULE_NAME] firewall rule on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
		exit 1
	fi
else
	echo "[$FIREWALL_RULE_NAME] firewall rule already exists on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
fi

# Check if the PostgreSQL database already exists
echo "Checking if [$POSTGRES_DATABASE_NAME] database already exists on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."
az postgres flexible-server db show \
	--server-name $POSTGRES_SERVER_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--database-name $POSTGRES_DATABASE_NAME \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$POSTGRES_DATABASE_NAME] database already exists on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
	echo "Creating [$POSTGRES_DATABASE_NAME] database on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."

	# Create the application database
	az postgres flexible-server db create \
		--server-name $POSTGRES_SERVER_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--database-name $POSTGRES_DATABASE_NAME \
		--charset UTF8 \
		--collation en_US.utf8 \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "[$POSTGRES_DATABASE_NAME] database successfully created on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
	else
		echo "Failed to create [$POSTGRES_DATABASE_NAME] database on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
		exit 1
	fi
else
	echo "[$POSTGRES_DATABASE_NAME] database already exists on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
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
		--tags environment=test iac=az-cli \
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
		--tags environment=test iac=az-cli \
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
		--tags environment=test iac=az-cli \
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
		--tags environment=test iac=az-cli \
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
		--tags environment=test iac=az-cli \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$VIRTUAL_NETWORK_NAME] virtual network successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$VIRTUAL_NETWORK_NAME] virtual network in the [$RESOURCE_GROUP_NAME] resource group"
		exit
	fi

	# Update the web app subnet to associate it with the NAT Gateway and the NSG
	echo "Associating [$WEB_APP_SUBNET_NAME] subnet with the [$NAT_GATEWAY_NAME] NAT Gateway and the [$WEB_APP_SUBNET_NSG_NAME] network security group..."

	# Update the web app subnet to associate it with the NAT Gateway and the NSG
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
	--only-show-errors \
	--query id \
	--output tsv)

if [[ -n $VIRTUAL_NETWORK_ID ]]; then
	echo "[$VIRTUAL_NETWORK_NAME] virtual network resource id retrieved successfully: $VIRTUAL_NETWORK_ID"
else
	echo "Failed to retrieve [$VIRTUAL_NETWORK_NAME] virtual network resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit
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
		--tags environment=test iac=az-cli \
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
	echo "Creating [$PRIVATE_ENDPOINT_NAME] private endpoint for the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create a private endpoint for the PostgreSQL flexible server
	az network private-endpoint create \
		--name "$PRIVATE_ENDPOINT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--vnet-name "$VIRTUAL_NETWORK_NAME" \
		--subnet "$PE_SUBNET_NAME" \
		--private-connection-resource-id "$POSTGRES_SERVER_ID" \
		--group-id "$PRIVATE_ENDPOINT_GROUP" \
		--connection-name "postgres-connection" \
		--tags environment=test iac=az-cli \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Private endpoint [$PRIVATE_ENDPOINT_NAME] successfully created for the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create a private endpoint for the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server in the [$RESOURCE_GROUP_NAME] resource group"
		exit
	fi
else
	echo "Private endpoint [$PRIVATE_ENDPOINT_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the private DNS zone group is already created for the PostgreSQL flexible server private endpoint
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

	# Create the private DNS zone group for the PostgreSQL flexible server private endpoint
	az network private-endpoint dns-zone-group create \
		--name "$PRIVATE_DNS_ZONE_GROUP_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--endpoint-name "$PRIVATE_ENDPOINT_NAME" \
		--private-dns-zone "$PRIVATE_DNS_ZONE_NAME" \
		--zone-name "postgres-zone" \
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

# Create application role [$PG_APP_USER] on the PostgreSQL flexible server
echo "Creating login [$PG_APP_USER] on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."
PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_ADMIN_USER" \
	--dbname=postgres \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "DO \$\$
BEGIN
	IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$PG_APP_USER') THEN
		CREATE ROLE \"$PG_APP_USER\" WITH LOGIN PASSWORD '$PG_APP_PASSWORD';
	END IF;
END
\$\$;"

if [ $? -eq 0 ]; then
	echo "Login [$PG_APP_USER] created successfully"
else
	echo "Failed to create login [$PG_APP_USER]"
	exit 1
fi

# Grant CONNECT on the database to [$PG_APP_USER]
echo "Granting CONNECT on [$POSTGRES_DATABASE_NAME] to [$PG_APP_USER]..."
PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_ADMIN_USER" \
	--dbname=postgres \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "GRANT CONNECT ON DATABASE \"$POSTGRES_DATABASE_NAME\" TO \"$PG_APP_USER\";"

if [ $? -eq 0 ]; then
	echo "CONNECT granted successfully to [$PG_APP_USER]"
else
	echo "Failed to grant CONNECT to [$PG_APP_USER]"
	exit 1
fi

# Grant schema privileges to [$PG_APP_USER]
echo "Granting schema privileges on [$POSTGRES_DATABASE_NAME] to [$PG_APP_USER]..."
PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_ADMIN_USER" \
	--dbname="$POSTGRES_DATABASE_NAME" \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "GRANT USAGE, CREATE ON SCHEMA public TO \"$PG_APP_USER\";
		ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"$PG_APP_USER\";
		ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"$PG_APP_USER\";"

if [ $? -eq 0 ]; then
	echo "Schema privileges granted successfully to [$PG_APP_USER]"
else
	echo "Failed to grant schema privileges to [$PG_APP_USER]"
	exit 1
fi

# Test connection
echo "Testing connection with user [$PG_APP_USER]..."
PGPASSWORD="$PG_APP_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_APP_USER" \
	--dbname="$POSTGRES_DATABASE_NAME" \
	--no-password \
	-c "SELECT current_user, current_database(), now();"

if [ $? -eq 0 ]; then
	echo "Connection test successful with user [$PG_APP_USER]"
else
	echo "Connection test failed with user [$PG_APP_USER]"
	exit 1
fi

# Create [activities] table
echo "Creating [activities] table in the [$POSTGRES_DATABASE_NAME] database..."
PGPASSWORD="$PG_APP_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_APP_USER" \
	--dbname="$POSTGRES_DATABASE_NAME" \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "CREATE TABLE IF NOT EXISTS activities (
			id           TEXT PRIMARY KEY,
			username     TEXT NOT NULL,
			activity     TEXT NOT NULL,
			created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
		CREATE INDEX IF NOT EXISTS idx_activities_username ON activities(username);
		CREATE INDEX IF NOT EXISTS idx_activities_created_at ON activities(created_at DESC);"

if [ $? -eq 0 ]; then
	echo "[activities] table created successfully"
else
	echo "Failed to create [activities] table"
	exit 1
fi

# Insert sample data
echo "Inserting sample data into [activities] table..."
PGPASSWORD="$PG_APP_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_APP_USER" \
	--dbname="$POSTGRES_DATABASE_NAME" \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "INSERT INTO activities (id, username, activity) VALUES
			(md5('paolo_pisa_seed'), 'paolo', 'Visit the Leaning Tower in Pisa'),
      (md5('paolo_volterra_seed'), 'paolo', 'Explore Etruscan walls in Volterra'),
      (md5('paolo_san_gimignano_seed'), 'paolo', 'Climb Torre Grossa in San Gimignano'),
      (md5('paolo_siena_seed'), 'paolo', 'Walk across Piazza del Campo in Siena'),
      (md5('paolo_montalcino_seed'), 'paolo', 'Taste Brunello wine in Montalcino'),
      (md5('paolo_pienza_seed'), 'paolo', 'Sample Pecorino cheese in Pienza'),
      (md5('paolo_florence_seed'), 'paolo', 'Admire Michelangelo''s David in Florence'),
      (md5('paolo_viareggio_beach_seed'), 'paolo', 'Relax by the beach in Viareggio'),
      (md5('paolo_viareggio_promenade_seed'), 'paolo', 'Stroll along the Viareggio promenade')
		ON CONFLICT (id) DO NOTHING;"

if [ $? -eq 0 ]; then
	echo "Sample data inserted successfully into [activities] table"
else
	echo "Failed to insert sample data into [activities] table"
	exit 1
fi

# Query sample data
echo "Querying sample data from [activities] table..."
PGPASSWORD="$PG_APP_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_APP_USER" \
	--dbname="$POSTGRES_DATABASE_NAME" \
	--no-password \
	-c "SELECT * FROM activities;"

if [ $? -eq 0 ]; then
	echo "Sample data queried successfully from [activities] table"
else
	echo "Failed to query sample data from [activities] table"
	exit 1
fi

# Create app service plan
echo "Creating app service plan [$APP_SERVICE_PLAN_NAME]..."
az appservice plan create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_SERVICE_PLAN_NAME" \
	--location "$LOCATION" \
	--sku "$APP_SERVICE_PLAN_SKU" \
	--is-linux \
	--tags environment=test iac=az-cli \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "app service plan [$APP_SERVICE_PLAN_NAME] created successfully."
else
	echo "Failed to create app service plan [$APP_SERVICE_PLAN_NAME]."
	exit 1
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

# Create the web app
echo "Creating web app [$WEB_APP_NAME]..."
az webapp create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--plan "$APP_SERVICE_PLAN_NAME" \
	--name "$WEB_APP_NAME" \
	--runtime "$RUNTIME:$RUNTIME_VERSION" \
	--vnet "$VIRTUAL_NETWORK_NAME" \
	--subnet "$WEB_APP_SUBNET_NAME" \
	--tags environment=test iac=az-cli \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app [$WEB_APP_NAME] created successfully."
else
	echo "Failed to create web app [$WEB_APP_NAME]."
	exit 1
fi

# Get the web app resource id
echo "Getting [$WEB_APP_NAME] web app resource id in the [$RESOURCE_GROUP_NAME] resource group..."
WEB_APP_ID=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $WEB_APP_ID ]]; then
	echo "[$WEB_APP_NAME] web app resource id retrieved successfully: $WEB_APP_ID"
else
	echo "Failed to retrieve [$WEB_APP_NAME] web app resource id in the [$RESOURCE_GROUP_NAME] resource group"
	exit 1
fi

# Enabling forced tunneling for web app [$WEB_APP_NAME] to route all outbound traffic through the virtual network...
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
echo "Setting web app settings for [$WEB_APP_NAME]..."
az webapp config appsettings set \
	--name $WEB_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	PG_HOST="$POSTGRES_FQDN" \
	PG_PORT="$POSTGRES_PORT" \
	PG_USER="$PG_APP_USER" \
	PG_PASSWORD="$PG_APP_PASSWORD" \
	PG_DATABASE="$POSTGRES_DATABASE_NAME" \
	LOGIN_NAME="$LOGIN_NAME" \
	WEBSITES_PORT="8000" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app settings for [$WEB_APP_NAME] set successfully."
else
	echo "Failed to set web app settings for [$WEB_APP_NAME]."
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
		--tags environment=test iac=az-cli \
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

# Check whether the diagnostic settings for the PostgreSQL flexible server already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$POSTGRES_SERVER_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."

	# Create the diagnostic settings for the PostgreSQL flexible server to send logs to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$POSTGRES_SERVER_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "PostgreSQLLogs", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server already exist"
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

# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py database.py gunicorn.conf.py static templates requirements.txt

# List the contents of the zip package
echo "Contents of the zip package [$ZIPFILE]:"
unzip -l "$ZIPFILE"

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
echo "Using standard az webapp deploy command for AzureCloud environment."
az webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Print the list of resources in the resource group
echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table 
