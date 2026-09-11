#!/bin/bash

# Variables
# Every default below can be overridden through the environment, for example
#   SUFFIX=<unique> PG_APP_PASSWORD=<password> bash deploy.sh
# The App Configuration store and the Key Vault have globally unique names on Azure, so a run against a
# real subscription normally needs its own SUFFIX (or PREFIX).
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION="${LOCATION:-westeurope}"
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
PRIVATE_DNS_ZONE_GROUP_NAME="default"
POSTGRES_PRIVATE_DNS_ZONE_NAME="privatelink.postgres.database.azure.com"
POSTGRES_PRIVATE_ENDPOINT_NAME="${PREFIX}-postgres-pe-${SUFFIX}"
POSTGRES_PRIVATE_ENDPOINT_GROUP="postgresqlServer"
APP_CONFIG_NAME="${PREFIX}-appconfig-${SUFFIX}"
APP_CONFIG_SKU="${APP_CONFIG_SKU:-Standard}"
APP_CONFIG_PRIVATE_DNS_ZONE_NAME="privatelink.azconfig.io"
APP_CONFIG_PRIVATE_ENDPOINT_NAME="${PREFIX}-appconfig-pe-${SUFFIX}"
APP_CONFIG_PRIVATE_ENDPOINT_GROUP="configurationStores"
KEY_VAULT_NAME="${PREFIX}-keyvault-${SUFFIX}"
KEY_VAULT_PRIVATE_DNS_ZONE_NAME="privatelink.vaultcore.azure.net"
KEY_VAULT_PRIVATE_ENDPOINT_NAME="${PREFIX}-keyvault-pe-${SUFFIX}"
KEY_VAULT_PRIVATE_ENDPOINT_GROUP="vault"
KEY_VAULT_REFERENCE_CONTENT_TYPE="application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8"
PG_USER_SECRET_NAME="pg-user"
PG_PASSWORD_SECRET_NAME="pg-password"
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}"
APP_CONFIG_DATA_READER_ROLE="App Configuration Data Reader"
KEY_VAULT_SECRETS_USER_ROLE="Key Vault Secrets User"
KEY_VAULT_SECRETS_OFFICER_ROLE="Key Vault Secrets Officer"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="S1"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
POSTGRES_SERVER_NAME="${PREFIX}-pgflex-${SUFFIX}"
POSTGRES_VERSION="16"
POSTGRES_SKU_NAME="Standard_B1ms"
POSTGRES_SKU_TIER="Burstable"
POSTGRES_STORAGE_SIZE_GB=32
POSTGRES_BACKUP_RETENTION_DAYS=7
POSTGRES_DATABASE_NAME="${PG_DATABASE_NAME:-PlannerDB}"
PG_ADMIN_USER="${PG_ADMIN_USER:-pgadmin}"
PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:-P@ssw0rd1234!}"
PG_APP_USER="${PG_APP_USER:-testuser}"
PG_APP_PASSWORD="${PG_APP_PASSWORD:-TestP@ssw0rd123}"
FIREWALL_RULE_NAME="AllowAllIPs"
RUNTIME="dotnetcore"
RUNTIME_VERSION="10.0"
LOGIN_NAME="${LOGIN_NAME:-paolo}"
DEPLOY_APP="${DEPLOY_APP:-1}"
ROLE_ASSIGNMENT_RETRY_COUNT=3
ROLE_ASSIGNMENT_RETRY_SLEEP=5
SECRET_RETRY_COUNT=20
SECRET_RETRY_SLEEP=30
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

#********************************************
# Functions
#********************************************

# Create a private DNS zone in the resource group, unless it already exists.
# $1: the zone name
ensure_private_dns_zone() {
	local zone_name=$1

	echo "Checking if [$zone_name] private DNS zone actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
	az network private-dns zone show \
		--name "$zone_name" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--only-show-errors &>/dev/null

	if [[ $? != 0 ]]; then
		echo "No [$zone_name] private DNS zone actually exists in the [$RESOURCE_GROUP_NAME] resource group"
		echo "Creating [$zone_name] private DNS zone in the [$RESOURCE_GROUP_NAME] resource group..."

		az network private-dns zone create \
			--name "$zone_name" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--tags environment=test iac=az-cli \
			--only-show-errors 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "[$zone_name] private DNS zone successfully created in the [$RESOURCE_GROUP_NAME] resource group"
		else
			echo "Failed to create [$zone_name] private DNS zone in the [$RESOURCE_GROUP_NAME] resource group"
			exit 1
		fi
	else
		echo "[$zone_name] private DNS zone already exists in the [$RESOURCE_GROUP_NAME] resource group"
	fi
}

# Link a private DNS zone to the sample's virtual network, unless the link already exists.
# $1: the zone name
ensure_private_dns_zone_link() {
	local zone_name=$1

	echo "Checking if [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$zone_name] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network actually exists..."
	az network private-dns link vnet show \
		--name "$VIRTUAL_NETWORK_LINK_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--zone-name "$zone_name" \
		--only-show-errors &>/dev/null

	if [[ $? != 0 ]]; then
		echo "No [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$zone_name] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network actually exists"
		echo "Creating [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$zone_name] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network..."

		az network private-dns link vnet create \
			--name "$VIRTUAL_NETWORK_LINK_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--zone-name "$zone_name" \
			--virtual-network "$VIRTUAL_NETWORK_ID" \
			--registration-enabled false \
			--only-show-errors 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "[$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$zone_name] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network successfully created"
		else
			echo "Failed to create [$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$zone_name] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network"
			exit 1
		fi
	else
		echo "[$VIRTUAL_NETWORK_LINK_NAME] virtual network link between [$zone_name] private DNS zone and [$VIRTUAL_NETWORK_NAME] virtual network already exists"
	fi
}

# Create a private endpoint in the private endpoint subnet for a target resource, unless it already exists.
# $1: the private endpoint name
# $2: the resource id of the target resource
# $3: the group id (sub-resource) of the target resource
# $4: the connection name
# $5: the description of the target resource, used in messages
ensure_private_endpoint() {
	local name=$1
	local resource_id=$2
	local group_id=$3
	local connection_name=$4
	local description=$5
	local private_endpoint_id

	echo "Checking if private endpoint [$name] exists in the [$RESOURCE_GROUP_NAME] resource group..."
	private_endpoint_id=$(az network private-endpoint list \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--only-show-errors \
		--query "[?name=='$name'].id" \
		--output tsv)

	if [[ -z $private_endpoint_id ]]; then
		echo "Private endpoint [$name] does not exist in the [$RESOURCE_GROUP_NAME] resource group"
		echo "Creating [$name] private endpoint for the $description in the [$RESOURCE_GROUP_NAME] resource group..."

		az network private-endpoint create \
			--name "$name" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--location "$LOCATION" \
			--vnet-name "$VIRTUAL_NETWORK_NAME" \
			--subnet "$PE_SUBNET_NAME" \
			--private-connection-resource-id "$resource_id" \
			--group-id "$group_id" \
			--connection-name "$connection_name" \
			--tags environment=test iac=az-cli \
			--only-show-errors 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "Private endpoint [$name] successfully created for the $description in the [$RESOURCE_GROUP_NAME] resource group"
		else
			echo "Failed to create a private endpoint for the $description in the [$RESOURCE_GROUP_NAME] resource group"
			exit 1
		fi
	else
		echo "Private endpoint [$name] already exists in the [$RESOURCE_GROUP_NAME] resource group"
	fi
}

# Create the private DNS zone group that registers the private endpoint's A record in a zone, unless it already exists.
# $1: the private endpoint name
# $2: the zone name
# $3: the name of the zone configuration inside the group
ensure_private_dns_zone_group() {
	local endpoint_name=$1
	local zone_name=$2
	local zone_config_name=$3
	local current_name

	echo "Checking if the private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$endpoint_name] private endpoint already exists..."
	current_name=$(az network private-endpoint dns-zone-group show \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--endpoint-name "$endpoint_name" \
		--name "$PRIVATE_DNS_ZONE_GROUP_NAME" \
		--query name \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ -z $current_name ]]; then
		echo "No private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$endpoint_name] private endpoint actually exists"
		echo "Creating private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$endpoint_name] private endpoint..."

		az network private-endpoint dns-zone-group create \
			--name "$PRIVATE_DNS_ZONE_GROUP_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--endpoint-name "$endpoint_name" \
			--private-dns-zone "$zone_name" \
			--zone-name "$zone_config_name" \
			--only-show-errors 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "Private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$endpoint_name] private endpoint successfully created"
		else
			echo "Failed to create private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$endpoint_name] private endpoint"
			exit 1
		fi
	else
		echo "Private DNS zone group [$PRIVATE_DNS_ZONE_GROUP_NAME] for the [$endpoint_name] private endpoint already exists"
	fi
}

# Assign a role to a principal at a scope, unless the assignment already exists. The assignee is given as an
# object id together with its principal type, so no directory lookup happens at creation time.
# $1: the object id of the principal
# $2: the principal type (ServicePrincipal, User or Group)
# $3: the role name
# $4: the scope (resource id)
# $5: the description of the principal, used in messages
# $6: the description of the scope, used in messages
ensure_role_assignment() {
	local principal_id=$1
	local principal_type=$2
	local role=$3
	local scope=$4
	local principal_description=$5
	local scope_description=$6
	local current attempt

	echo "Checking if the $principal_description has the [$role] role assignment on the $scope_description..."
	current=$(az role assignment list \
		--assignee "$principal_id" \
		--scope "$scope" \
		--query "[?roleDefinitionName=='$role'].roleDefinitionName" \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ $current == "$role" ]]; then
		echo "The $principal_description already has the [$role] role assignment on the $scope_description"
		return 0
	fi

	echo "Assigning the [$role] role to the $principal_description on the $scope_description..."
	for attempt in $(seq 1 "$ROLE_ASSIGNMENT_RETRY_COUNT"); do
		if az role assignment create \
			--assignee-object-id "$principal_id" \
			--assignee-principal-type "$principal_type" \
			--role "$role" \
			--scope "$scope" \
			--only-show-errors 1>/dev/null; then
			echo "[$role] role successfully assigned to the $principal_description on the $scope_description"
			return 0
		fi

		if [ "$attempt" -lt "$ROLE_ASSIGNMENT_RETRY_COUNT" ]; then
			echo "Attempt $attempt of $ROLE_ASSIGNMENT_RETRY_COUNT to assign the [$role] role failed; retrying in $ROLE_ASSIGNMENT_RETRY_SLEEP seconds..."
			sleep "$ROLE_ASSIGNMENT_RETRY_SLEEP"
		fi
	done

	echo "Failed to assign the [$role] role to the $principal_description on the $scope_description"
	exit 1
}

# Store a secret in the key vault, unless it already holds the same value. The value is never printed.
# Reads and writes go through the Key Vault data plane, which the deploying principal can use only once its
# Key Vault Secrets Officer assignment has propagated, so the write is retried for a few minutes.
# $1: the secret name
# $2: the secret value
set_secret() {
	local secret_name=$1
	local secret_value=$2
	local current attempt

	echo "Checking if the [$secret_name] secret actually exists in the [$KEY_VAULT_NAME] key vault..."
	current=$(az keyvault secret show \
		--vault-name "$KEY_VAULT_NAME" \
		--name "$secret_name" \
		--query value \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ -n $current && $current == "$secret_value" ]]; then
		echo "The [$secret_name] secret already holds the expected value in the [$KEY_VAULT_NAME] key vault"
		return 0
	fi

	echo "Setting the [$secret_name] secret in the [$KEY_VAULT_NAME] key vault..."
	for attempt in $(seq 1 "$SECRET_RETRY_COUNT"); do
		if az keyvault secret set \
			--vault-name "$KEY_VAULT_NAME" \
			--name "$secret_name" \
			--value "$secret_value" \
			--only-show-errors 1>/dev/null; then
			echo "The [$secret_name] secret was successfully set in the [$KEY_VAULT_NAME] key vault"
			return 0
		fi

		if [ "$attempt" -lt "$SECRET_RETRY_COUNT" ]; then
			echo "Attempt $attempt of $SECRET_RETRY_COUNT to set the [$secret_name] secret failed (the [$KEY_VAULT_SECRETS_OFFICER_ROLE] assignment may still be propagating); retrying in $SECRET_RETRY_SLEEP seconds..."
			sleep "$SECRET_RETRY_SLEEP"
		fi
	done

	echo "Failed to set the [$secret_name] secret in the [$KEY_VAULT_NAME] key vault"
	exit 1
}

# Set a plain key-value in the App Configuration store, unless it already holds the same value.
# $1: the key
# $2: the value
set_key_value() {
	local key=$1
	local value=$2
	local current

	echo "Checking if the [$key] key actually exists in the [$APP_CONFIG_NAME] App Configuration store..."
	current=$(az appconfig kv show \
		--name "$APP_CONFIG_NAME" \
		--key "$key" \
		--query value \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ $? == 0 && $current == "$value" ]]; then
		echo "The [$key] key already holds the [$value] value in the [$APP_CONFIG_NAME] App Configuration store"
		return 0
	fi

	echo "Setting the [$key] key to the [$value] value in the [$APP_CONFIG_NAME] App Configuration store..."
	az appconfig kv set \
		--name "$APP_CONFIG_NAME" \
		--key "$key" \
		--value "$value" \
		--yes \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "The [$key] key was successfully set to the [$value] value"
	else
		echo "Failed to set the [$key] key in the [$APP_CONFIG_NAME] App Configuration store"
		exit 1
	fi
}

# Set a Key Vault reference in the App Configuration store, unless it already points at the same secret.
# A Key Vault reference is a key-value whose content type is
# application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8 and whose value is {"uri":"<secret identifier>"}.
# The identifier carries no version, so the reference always follows the latest version of the secret.
# $1: the key
# $2: the secret identifier
set_key_vault_reference() {
	local key=$1
	local secret_identifier=$2
	local current

	echo "Checking if the [$key] key actually exists in the [$APP_CONFIG_NAME] App Configuration store..."
	current=$(az appconfig kv show \
		--name "$APP_CONFIG_NAME" \
		--key "$key" \
		--query "join('|', [contentType, value])" \
		--output tsv \
		--only-show-errors 2>/dev/null)

	if [[ $current == "$KEY_VAULT_REFERENCE_CONTENT_TYPE|"*"\"$secret_identifier\""* ]]; then
		echo "The [$key] key already references the [$secret_identifier] secret"
		return 0
	fi

	echo "Setting the [$key] key as a reference to the [$secret_identifier] secret..."
	az appconfig kv set-keyvault \
		--name "$APP_CONFIG_NAME" \
		--key "$key" \
		--secret-identifier "$secret_identifier" \
		--yes \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "The [$key] key was successfully set as a reference to the [$secret_identifier] secret"
	else
		echo "Failed to set the [$key] key in the [$APP_CONFIG_NAME] App Configuration store"
		exit 1
	fi
}

#********************************************
# Resource group
#********************************************

# Create a resource group
echo "Creating resource group [$RESOURCE_GROUP_NAME]..."
az group create \
	--name "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--tags environment=test iac=az-cli \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Resource group [$RESOURCE_GROUP_NAME] created successfully."
else
	echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
	exit 1
fi

#********************************************
# User-assigned managed identity
#********************************************

# Check if the user-assigned managed identity already exists
echo "Checking if [$MANAGED_IDENTITY_NAME] user-assigned managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$MANAGED_IDENTITY_NAME] user-assigned managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$MANAGED_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the user-assigned managed identity the web app uses to reach App Configuration and Key Vault
	az identity create \
		--name "$MANAGED_IDENTITY_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--tags environment=test iac=az-cli \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$MANAGED_IDENTITY_NAME] user-assigned managed identity successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$MANAGED_IDENTITY_NAME] user-assigned managed identity in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$MANAGED_IDENTITY_NAME] user-assigned managed identity already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Retrieve the clientId, principalId and resource id of the user-assigned managed identity
echo "Retrieving the clientId, principalId and resource id of the [$MANAGED_IDENTITY_NAME] managed identity..."
mapfile -t IDENTITY_FIELDS < <(az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[clientId, principalId, id]" \
	--output tsv \
	--only-show-errors)
IDENTITY_CLIENT_ID="${IDENTITY_FIELDS[0]:-}"
IDENTITY_PRINCIPAL_ID="${IDENTITY_FIELDS[1]:-}"
IDENTITY_ID="${IDENTITY_FIELDS[2]:-}"

if [[ -n $IDENTITY_CLIENT_ID && -n $IDENTITY_PRINCIPAL_ID && -n $IDENTITY_ID ]]; then
	echo "[$MANAGED_IDENTITY_NAME] managed identity: clientId [$IDENTITY_CLIENT_ID], principalId [$IDENTITY_PRINCIPAL_ID]"
else
	echo "Failed to retrieve the clientId, principalId and resource id of the [$MANAGED_IDENTITY_NAME] managed identity"
	exit 1
fi

#********************************************
# App Configuration store
#********************************************

# Recover the App Configuration store if a previous run left it soft-deleted.
# Deleting a Standard store only soft-deletes it and the name stays reserved for the retention period, so
# re-running this script after deleting the resource group would fail the create below.
DELETED_APP_CONFIG_LOCATION=$(az appconfig list-deleted \
	--query "[?name=='$APP_CONFIG_NAME'].location | [0]" \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $DELETED_APP_CONFIG_LOCATION ]]; then
	echo "[$APP_CONFIG_NAME] App Configuration store exists in a soft-deleted state in [$DELETED_APP_CONFIG_LOCATION]"
	echo "Recovering the [$APP_CONFIG_NAME] App Configuration store..."

	az appconfig recover \
		--name "$APP_CONFIG_NAME" \
		--location "$DELETED_APP_CONFIG_LOCATION" \
		--yes \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$APP_CONFIG_NAME] App Configuration store successfully recovered"
	else
		echo "Failed to recover the soft-deleted [$APP_CONFIG_NAME] App Configuration store"
		echo "Purge it and re-run this script:"
		echo "  az appconfig purge --name $APP_CONFIG_NAME --location $DELETED_APP_CONFIG_LOCATION --yes"
		exit 1
	fi
fi

# Check if the App Configuration store already exists
echo "Checking if [$APP_CONFIG_NAME] App Configuration store actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az appconfig show \
	--name "$APP_CONFIG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APP_CONFIG_NAME] App Configuration store actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$APP_CONFIG_NAME] App Configuration store in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the App Configuration store. Access keys stay enabled (the default): the az appconfig kv commands
	# below authenticate with them, and the Bicep and Terraform variants write key-values through Azure Resource
	# Manager, which in the default Local authentication mode also relies on them.
	# Public network access is enabled explicitly: when the property is left unspecified, Azure disables it as
	# soon as the store gets a private endpoint, and the data-plane calls of this script and of validate.sh
	# (az appconfig kv ...) come from outside the virtual network. The web app reaches the store through the
	# private endpoint either way.
	az appconfig create \
		--name "$APP_CONFIG_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--sku "$APP_CONFIG_SKU" \
		--enable-public-network true \
		--tags environment=test iac=az-cli \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$APP_CONFIG_NAME] App Configuration store successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$APP_CONFIG_NAME] App Configuration store in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$APP_CONFIG_NAME] App Configuration store already exists in the [$RESOURCE_GROUP_NAME] resource group"

	# Make sure public network access stays enabled on an existing store (see the comment above)
	APP_CONFIG_PUBLIC_ACCESS=$(az appconfig show \
		--name "$APP_CONFIG_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query publicNetworkAccess \
		--output tsv \
		--only-show-errors)

	if [[ $APP_CONFIG_PUBLIC_ACCESS != "Enabled" ]]; then
		echo "Enabling public network access on the [$APP_CONFIG_NAME] App Configuration store (currently [$APP_CONFIG_PUBLIC_ACCESS])..."

		az appconfig update \
			--name "$APP_CONFIG_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--enable-public-network true \
			--only-show-errors 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "Public network access enabled on the [$APP_CONFIG_NAME] App Configuration store"
		else
			echo "Failed to enable public network access on the [$APP_CONFIG_NAME] App Configuration store"
			exit 1
		fi
	fi
fi

# Retrieve the endpoint and the resource id of the App Configuration store. The endpoint is read back from
# the service and used verbatim by the web app: https://<store>.azconfig.io on Azure,
# https://<store>.azure.localhost.localstack.cloud:4566 on the emulator.
echo "Retrieving the endpoint and the resource id of the [$APP_CONFIG_NAME] App Configuration store..."
mapfile -t APP_CONFIG_FIELDS < <(az appconfig show \
	--name "$APP_CONFIG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[endpoint, id]" \
	--output tsv \
	--only-show-errors)
APP_CONFIG_ENDPOINT="${APP_CONFIG_FIELDS[0]:-}"
APP_CONFIG_ID="${APP_CONFIG_FIELDS[1]:-}"

if [[ -n $APP_CONFIG_ENDPOINT && -n $APP_CONFIG_ID ]]; then
	echo "[$APP_CONFIG_NAME] App Configuration store endpoint: $APP_CONFIG_ENDPOINT"
else
	echo "Failed to retrieve the endpoint and the resource id of the [$APP_CONFIG_NAME] App Configuration store"
	exit 1
fi

#********************************************
# Key Vault
#********************************************

# Recover the key vault if a previous run left it soft-deleted.
# Deleting a key vault only soft-deletes it, and the name stays reserved for the retention period, so
# re-running this script after deleting the resource group fails the create below with
# "A vault with the same name already exists in deleted state". Recovering restores the vault with its
# contents, which is what a re-run wants; purging would throw them away.
# The vault's own location, not $LOCATION: a soft-deleted vault stays in the region it was deleted in,
# so recovering (or purging) it with a different region fails.
DELETED_KEY_VAULT_LOCATION=$(az keyvault list-deleted \
	--query "[?name=='$KEY_VAULT_NAME'].properties.location | [0]" \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $DELETED_KEY_VAULT_LOCATION ]]; then
	echo "[$KEY_VAULT_NAME] key vault exists in a soft-deleted state in [$DELETED_KEY_VAULT_LOCATION]"
	echo "Recovering the [$KEY_VAULT_NAME] key vault..."

	az keyvault recover \
		--name "$KEY_VAULT_NAME" \
		--location "$DELETED_KEY_VAULT_LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$KEY_VAULT_NAME] key vault successfully recovered"
	else
		echo "Failed to recover the soft-deleted [$KEY_VAULT_NAME] key vault"
		echo "Purge it and re-run this script:"
		echo "  az keyvault purge --name $KEY_VAULT_NAME --location $DELETED_KEY_VAULT_LOCATION"
		exit 1
	fi
fi

# Check if the key vault already exists
echo "Checking if [$KEY_VAULT_NAME] key vault actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az keyvault show \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$KEY_VAULT_NAME] key vault actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$KEY_VAULT_NAME] key vault in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the key vault with the Azure RBAC permission model: the Key Vault Secrets User role assigned to
	# the managed identity below only works on vaults that use it.
	az keyvault create \
		--name "$KEY_VAULT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--enable-rbac-authorization true \
		--retention-days 7 \
		--tags environment=test iac=az-cli \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$KEY_VAULT_NAME] key vault successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$KEY_VAULT_NAME] key vault in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$KEY_VAULT_NAME] key vault already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Retrieve the vault URI and the resource id of the key vault. The URI is read back from the service:
# https://<vault>.vault.azure.net/ on Azure, https://<vault>.vault.azure.localhost.localstack.cloud:4566/ on
# the emulator.
echo "Retrieving the vault URI and the resource id of the [$KEY_VAULT_NAME] key vault..."
mapfile -t KEY_VAULT_FIELDS < <(az keyvault show \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[properties.vaultUri, id]" \
	--output tsv \
	--only-show-errors)
KEY_VAULT_URI="${KEY_VAULT_FIELDS[0]:-}"
KEY_VAULT_ID="${KEY_VAULT_FIELDS[1]:-}"

if [[ -n $KEY_VAULT_URI && -n $KEY_VAULT_ID ]]; then
	echo "[$KEY_VAULT_NAME] key vault URI: $KEY_VAULT_URI"
else
	echo "Failed to retrieve the vault URI and the resource id of the [$KEY_VAULT_NAME] key vault"
	exit 1
fi

# Resolve the object id of the deploying principal. The vault uses the RBAC permission model, so writing
# the two secrets below needs the Key Vault Secrets Officer role on the vault; the script grants it to
# whoever runs it, a user or a service principal. The lookup goes through Microsoft Graph; when it fails
# the script continues and the role becomes a prerequisite (see the README).
ACCOUNT_USER_TYPE=$(az account show --query user.type --output tsv --only-show-errors)
ACCOUNT_USER_NAME=$(az account show --query user.name --output tsv --only-show-errors)

if [[ $ACCOUNT_USER_TYPE == "user" ]]; then
	DEPLOYER_PRINCIPAL_TYPE="User"
	DEPLOYER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv --only-show-errors 2>/dev/null)
else
	DEPLOYER_PRINCIPAL_TYPE="ServicePrincipal"
	DEPLOYER_OBJECT_ID=$(az ad sp show --id "$ACCOUNT_USER_NAME" --query id --output tsv --only-show-errors 2>/dev/null)
fi

# Microsoft Graph lookups need directory permissions a pipeline principal often lacks. Fall back to the oid
# claim of the CLI's own access token, which identifies the same principal without any Graph call.
if [[ -z $DEPLOYER_OBJECT_ID ]]; then
	DEPLOYER_OBJECT_ID=$(az account get-access-token --query accessToken --output tsv --only-show-errors 2>/dev/null |
		cut -d. -f2 | tr '_-' '/+' | awk '{ pad = length($0) % 4; if (pad == 2) $0 = $0 "=="; else if (pad == 3) $0 = $0 "="; print }' |
		base64 -d 2>/dev/null | jq -r '.oid // empty' 2>/dev/null)
fi

if [[ -n $DEPLOYER_OBJECT_ID ]]; then
	echo "Deploying principal [$ACCOUNT_USER_NAME] ($DEPLOYER_PRINCIPAL_TYPE) has object id [$DEPLOYER_OBJECT_ID]"
	ensure_role_assignment "$DEPLOYER_OBJECT_ID" "$DEPLOYER_PRINCIPAL_TYPE" "$KEY_VAULT_SECRETS_OFFICER_ROLE" "$KEY_VAULT_ID" "deploying principal [$ACCOUNT_USER_NAME]" "[$KEY_VAULT_NAME] key vault"
else
	echo "WARNING: could not resolve the object id of the deploying principal [$ACCOUNT_USER_NAME]; the [$KEY_VAULT_SECRETS_OFFICER_ROLE] role on the [$KEY_VAULT_NAME] key vault must already be assigned to it"
fi

# Store the application role credentials as secrets. The web app never sees these values directly: it
# reads them through the App Configuration Key Vault references created further below.
set_secret "$PG_USER_SECRET_NAME" "$PG_APP_USER"
set_secret "$PG_PASSWORD_SECRET_NAME" "$PG_APP_PASSWORD"

PG_USER_SECRET_URI="${KEY_VAULT_URI%/}/secrets/${PG_USER_SECRET_NAME}"
PG_PASSWORD_SECRET_URI="${KEY_VAULT_URI%/}/secrets/${PG_PASSWORD_SECRET_NAME}"

#********************************************
# Role assignments of the managed identity
#********************************************

# The web app authenticates to both stores with the user-assigned managed identity: App Configuration Data
# Reader to read the key-values, Key Vault Secrets User to read the secrets behind the Key Vault references.
ensure_role_assignment "$IDENTITY_PRINCIPAL_ID" "ServicePrincipal" "$APP_CONFIG_DATA_READER_ROLE" "$APP_CONFIG_ID" "[$MANAGED_IDENTITY_NAME] managed identity" "[$APP_CONFIG_NAME] App Configuration store"
ensure_role_assignment "$IDENTITY_PRINCIPAL_ID" "ServicePrincipal" "$KEY_VAULT_SECRETS_USER_ROLE" "$KEY_VAULT_ID" "[$MANAGED_IDENTITY_NAME] managed identity" "[$KEY_VAULT_NAME] key vault"

#********************************************
# PostgreSQL flexible server
#********************************************

# Check if the PostgreSQL flexible server already exists
echo "Checking if [$POSTGRES_SERVER_NAME] PostgreSQL flexible server already exists in the [$RESOURCE_GROUP_NAME] resource group..."
az postgres flexible-server show \
	--name "$POSTGRES_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$POSTGRES_SERVER_NAME] PostgreSQL flexible server already exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$POSTGRES_SERVER_NAME] PostgreSQL flexible server in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create a PostgreSQL flexible server with public network access
	az postgres flexible-server create \
		--name "$POSTGRES_SERVER_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--tier "$POSTGRES_SKU_TIER" \
		--sku-name "$POSTGRES_SKU_NAME" \
		--version "$POSTGRES_VERSION" \
		--storage-size "$POSTGRES_STORAGE_SIZE_GB" \
		--backup-retention "$POSTGRES_BACKUP_RETENTION_DAYS" \
		--geo-redundant-backup Disabled \
		--admin-user "$PG_ADMIN_USER" \
		--admin-password "$PG_ADMIN_PASSWORD" \
		--public-access Enabled \
		--zonal-resiliency Disabled \
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
	--name "$POSTGRES_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
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
	--name "$POSTGRES_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "fullyQualifiedDomainName" \
	--output tsv \
	--only-show-errors)

if [ -n "$POSTGRES_FQDN_FULL" ]; then
	echo "PostgreSQL flexible server FQDN retrieved successfully: $POSTGRES_FQDN_FULL"
else
	echo "Failed to retrieve PostgreSQL flexible server FQDN."
	exit 1
fi

# Split host:port: the LocalStack emulator embeds the dynamically allocated TCP-proxy port
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
	--server-name "$POSTGRES_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FIREWALL_RULE_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$FIREWALL_RULE_NAME] firewall rule already exists on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
	echo "Creating [$FIREWALL_RULE_NAME] firewall rule on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."

	# Create a permissive firewall rule so the deploy machine can run the psql bootstrap.
	# The create is retried because this PUT intermittently answers 500 against the emulator while
	# the server finishes provisioning, and the Azure CLI's own retries all land within a few seconds.
	FIREWALL_RULE_CREATED=0
	for attempt in $(seq 1 5); do
		if az postgres flexible-server firewall-rule create \
			--server-name "$POSTGRES_SERVER_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--name "$FIREWALL_RULE_NAME" \
			--start-ip-address "0.0.0.0" \
			--end-ip-address "255.255.255.255" \
			--only-show-errors 1>/dev/null; then
			FIREWALL_RULE_CREATED=1
			break
		fi

		if [ "$attempt" -lt 5 ]; then
			echo "Attempt $attempt of 5 to create the [$FIREWALL_RULE_NAME] firewall rule failed; retrying in 10 seconds..."
			sleep 10
		fi
	done

	if [ $FIREWALL_RULE_CREATED -eq 1 ]; then
		echo "[$FIREWALL_RULE_NAME] firewall rule successfully created on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
	else
		# Not fatal: the rule governs public network access, which the emulator does not enforce, and
		# the psql bootstrap below fails loudly if the server is genuinely unreachable.
		echo "WARNING: could not create the [$FIREWALL_RULE_NAME] firewall rule on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server; continuing"
	fi
else
	echo "[$FIREWALL_RULE_NAME] firewall rule already exists on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
fi

# Check if the PostgreSQL database already exists
echo "Checking if [$POSTGRES_DATABASE_NAME] database already exists on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."
az postgres flexible-server db show \
	--server-name "$POSTGRES_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$POSTGRES_DATABASE_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$POSTGRES_DATABASE_NAME] database already exists on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
	echo "Creating [$POSTGRES_DATABASE_NAME] database on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."

	# Create the application database
	az postgres flexible-server db create \
		--server-name "$POSTGRES_SERVER_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$POSTGRES_DATABASE_NAME" \
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

#********************************************
# App Configuration key-values
#********************************************

# The connection settings the web app used to receive as app settings now live in the store: the host, port
# and database name as plain key-values, the application role credentials as Key Vault references to the
# secrets stored above. The keys keep the names of the former environment variables and carry no label.
set_key_value "PG_HOST" "$POSTGRES_FQDN"
set_key_value "PG_PORT" "$POSTGRES_PORT"
set_key_value "PG_DATABASE" "$POSTGRES_DATABASE_NAME"
set_key_vault_reference "PG_USER" "$PG_USER_SECRET_URI"
set_key_vault_reference "PG_PASSWORD" "$PG_PASSWORD_SECRET_URI"

#********************************************
# Networking
#********************************************

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

# Check if the private endpoint subnet already exists
echo "Checking if [$PE_SUBNET_NAME] subnet actually exists in the [$VIRTUAL_NETWORK_NAME] virtual network..."
az network vnet subnet show \
	--name "$PE_SUBNET_NAME" \
	--vnet-name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$PE_SUBNET_NAME] subnet actually exists in the [$VIRTUAL_NETWORK_NAME] virtual network"
	echo "Creating [$PE_SUBNET_NAME] subnet in the [$VIRTUAL_NETWORK_NAME] virtual network..."

	# Create the subnet that hosts the three private endpoints
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
		exit 1
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
	exit 1
fi

#********************************************
# Private DNS zones and private endpoints
#********************************************

# PostgreSQL flexible server: privatelink.postgres.database.azure.com, group postgresqlServer
ensure_private_dns_zone "$POSTGRES_PRIVATE_DNS_ZONE_NAME"
ensure_private_dns_zone_link "$POSTGRES_PRIVATE_DNS_ZONE_NAME"
ensure_private_endpoint "$POSTGRES_PRIVATE_ENDPOINT_NAME" "$POSTGRES_SERVER_ID" "$POSTGRES_PRIVATE_ENDPOINT_GROUP" "postgres-connection" "[$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
ensure_private_dns_zone_group "$POSTGRES_PRIVATE_ENDPOINT_NAME" "$POSTGRES_PRIVATE_DNS_ZONE_NAME" "postgres-zone"

# App Configuration store: privatelink.azconfig.io, group configurationStores
ensure_private_dns_zone "$APP_CONFIG_PRIVATE_DNS_ZONE_NAME"
ensure_private_dns_zone_link "$APP_CONFIG_PRIVATE_DNS_ZONE_NAME"
ensure_private_endpoint "$APP_CONFIG_PRIVATE_ENDPOINT_NAME" "$APP_CONFIG_ID" "$APP_CONFIG_PRIVATE_ENDPOINT_GROUP" "appconfig-connection" "[$APP_CONFIG_NAME] App Configuration store"
ensure_private_dns_zone_group "$APP_CONFIG_PRIVATE_ENDPOINT_NAME" "$APP_CONFIG_PRIVATE_DNS_ZONE_NAME" "appconfig-zone"

# Key Vault: privatelink.vaultcore.azure.net, group vault
ensure_private_dns_zone "$KEY_VAULT_PRIVATE_DNS_ZONE_NAME"
ensure_private_dns_zone_link "$KEY_VAULT_PRIVATE_DNS_ZONE_NAME"
ensure_private_endpoint "$KEY_VAULT_PRIVATE_ENDPOINT_NAME" "$KEY_VAULT_ID" "$KEY_VAULT_PRIVATE_ENDPOINT_GROUP" "keyvault-connection" "[$KEY_VAULT_NAME] key vault"
ensure_private_dns_zone_group "$KEY_VAULT_PRIVATE_ENDPOINT_NAME" "$KEY_VAULT_PRIVATE_DNS_ZONE_NAME" "keyvault-zone"

#********************************************
# PostgreSQL bootstrap
#********************************************

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

#********************************************
# App Service plan and web app
#********************************************

# Check if the app service plan already exists
echo "Checking if [$APP_SERVICE_PLAN_NAME] app service plan actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az appservice plan show \
	--name "$APP_SERVICE_PLAN_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APP_SERVICE_PLAN_NAME] app service plan actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating app service plan [$APP_SERVICE_PLAN_NAME]..."

	# Create the app service plan
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
else
	echo "[$APP_SERVICE_PLAN_NAME] app service plan already exists in the [$RESOURCE_GROUP_NAME] resource group"
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

# Check if the web app already exists
echo "Checking if web app [$WEB_APP_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group..."
az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No web app [$WEB_APP_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating web app [$WEB_APP_NAME] with the [$MANAGED_IDENTITY_NAME] user-assigned managed identity..."

	# Create the web app with regional VNet integration and the user-assigned managed identity
	az webapp create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--plan "$APP_SERVICE_PLAN_NAME" \
		--name "$WEB_APP_NAME" \
		--runtime "$RUNTIME:$RUNTIME_VERSION" \
		--vnet "$VIRTUAL_NETWORK_NAME" \
		--subnet "$WEB_APP_SUBNET_NAME" \
		--assign-identity "$IDENTITY_ID" \
		--tags environment=test iac=az-cli \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Web app [$WEB_APP_NAME] created successfully."
	else
		echo "Failed to create web app [$WEB_APP_NAME]."
		exit 1
	fi
else
	echo "Web app [$WEB_APP_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Making sure the [$MANAGED_IDENTITY_NAME] user-assigned managed identity is assigned to the [$WEB_APP_NAME] web app..."

	# Idempotent: assigning an identity that is already assigned is a no-op
	az webapp identity assign \
		--name "$WEB_APP_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--identities "$IDENTITY_ID" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "[$MANAGED_IDENTITY_NAME] user-assigned managed identity is assigned to the [$WEB_APP_NAME] web app"
	else
		echo "Failed to assign the [$MANAGED_IDENTITY_NAME] user-assigned managed identity to the [$WEB_APP_NAME] web app"
		exit 1
	fi
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

# Enable forced tunneling for the web app to route all outbound traffic through the virtual network
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

# Set web app settings. No PG_* setting is written: the web app loads them from the App Configuration
# store through the in-process provider, authenticating with the user-assigned managed identity that
# AZURE_CLIENT_ID selects. Endpoints__AppConfiguration is the app setting the provider reads the store
# endpoint from (the .NET variant sees it as Endpoints:AppConfiguration).
echo "Setting web app settings for [$WEB_APP_NAME]..."
az webapp config appsettings set \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--settings \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	Endpoints__AppConfiguration="$APP_CONFIG_ENDPOINT" \
	AZURE_CLIENT_ID="$IDENTITY_CLIENT_ID" \
	LOGIN_NAME="$LOGIN_NAME" \
	WEBSITES_PORT="8000" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app settings for [$WEB_APP_NAME] set successfully."
else
	echo "Failed to set web app settings for [$WEB_APP_NAME]."
	exit 1
fi

#********************************************
# Log Analytics and diagnostic settings
#********************************************

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

	# Create the diagnostic settings for the app service plan to send metrics to the Log Analytics workspace
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

# Check whether the diagnostic settings for the App Configuration store already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_CONFIG_NAME] App Configuration store already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$APP_CONFIG_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_CONFIG_NAME] App Configuration store actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_CONFIG_NAME] App Configuration store..."

	# Create the diagnostic settings for the App Configuration store to send logs to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$APP_CONFIG_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "HttpRequest", "enabled": true},
			{"category": "Audit", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_CONFIG_NAME] App Configuration store successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_CONFIG_NAME] App Configuration store"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_CONFIG_NAME] App Configuration store already exist"
fi

# Check whether the diagnostic settings for the key vault already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$KEY_VAULT_NAME] key vault already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$KEY_VAULT_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$KEY_VAULT_NAME] key vault actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$KEY_VAULT_NAME] key vault..."

	# Create the diagnostic settings for the key vault to send logs to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$KEY_VAULT_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "AuditEvent", "enabled": true},
			{"category": "AzurePolicyEvaluationDetails", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$KEY_VAULT_NAME] key vault successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$KEY_VAULT_NAME] key vault"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$KEY_VAULT_NAME] key vault already exist"
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

#********************************************
# Application deployment
#********************************************

if [[ $DEPLOY_APP == 1 ]]; then
	# Change current directory to source folder
	cd "../src" || exit

	# Remove any existing zip package of the web app
	if [ -f "$ZIPFILE" ]; then
		rm "$ZIPFILE"
	fi

	# Create the zip package of the web app
	echo "Creating zip package of the web app..."
	zip -r "$ZIPFILE" . -x "bin/*" "obj/*" "publish/*" "*.zip"

	# List the contents of the zip package
	echo "Contents of the zip package [$ZIPFILE]:"
	unzip -l "$ZIPFILE"

	# Deploy the web app
	echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
	az webapp deploy \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$WEB_APP_NAME" \
		--src-path "$ZIPFILE" \
		--type zip \
		--async true 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Web app [$WEB_APP_NAME] deployment started successfully."
	else
		echo "Failed to deploy web app [$WEB_APP_NAME]."
		exit 1
	fi

	# Remove the zip package of the web app
	if [ -f "$ZIPFILE" ]; then
		rm "$ZIPFILE"
	fi

	cd "$CURRENT_DIR" || exit
else
	echo "Skipping the deployment of the web app code (DEPLOY_APP=$DEPLOY_APP)"
fi

#********************************************
# Summary
#********************************************

# Print the key-values of the App Configuration store: PG_USER and PG_PASSWORD carry the Key Vault
# reference content type, the other three are plain values. The projection is done client-side with
# --query rather than with --fields: --fields makes the CLI request only those fields from the service,
# and the CLI then fails to build a Key Vault reference whose value was not returned.
echo "Key-values in the [$APP_CONFIG_NAME] App Configuration store:"
az appconfig kv list \
	--name "$APP_CONFIG_NAME" \
	--query "[].{Key:key,ContentType:contentType,Label:label}" \
	--output table \
	--only-show-errors

# Print the names (never the values) of the secrets in the key vault
echo "Secrets in the [$KEY_VAULT_NAME] key vault:"
az keyvault secret list \
	--vault-name "$KEY_VAULT_NAME" \
	--query "[].name" \
	--output tsv \
	--only-show-errors

# Print the list of resources in the resource group
echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table
