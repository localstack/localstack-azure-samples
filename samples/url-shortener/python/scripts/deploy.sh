#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}urlstorage${SUFFIX}"
LINKS_TABLE_NAME='links'
QR_JOBS_QUEUE_NAME='qrjobs'
QR_CONTAINER_NAME='qrcodes'
MANAGED_IDENTITY_NAME="${PREFIX}-urlshort-identity-${SUFFIX}"
KEY_VAULT_NAME="${PREFIX}-urlshort-kv-${SUFFIX}"
SIGN_KEY_SECRET_NAME='link-sign-key'
PG_CONN_SECRET_NAME='pg-conn'
POSTGRES_SERVER_NAME="${PREFIX}-urlshort-pgflex-${SUFFIX}"
POSTGRES_ADMIN_USER='linkletadmin'
POSTGRES_DB_NAME='clicks'
SERVICEBUS_NAMESPACE_NAME="${PREFIX}-urlshort-sb-ns-${SUFFIX}"
SERVICEBUS_QUEUE_NAME='link-events'
LOG_ANALYTICS_NAME="${PREFIX}-urlshort-log-analytics-${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-urlshort-insights-${SUFFIX}"
DIAGNOSTIC_SETTINGS_NAME='default'
APP_SERVICE_PLAN_NAME="${PREFIX}-urlshort-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU='B1'
WEB_APP_NAME="${PREFIX}-urlshort-webapp-${SUFFIX}"
FUNCTION_APP_NAME="${PREFIX}-urlshort-functionapp-${SUFFIX}"
RUNTIME='python'
WEB_APP_RUNTIME_VERSION='3.13'
FUNCTIONS_VERSION='4'
WEBAPP_ZIPFILE='linklet_webapp.zip'
WORKER_ZIPFILE='linklet_worker.zip'
DEPLOY_RETRY_COUNT=3
DEPLOY_RETRY_SLEEP=30
KEY_VAULT_SECRETS_OFFICER_ROLE="Key Vault Secrets Officer"
SECRET_RETRY_COUNT=20
SECRET_RETRY_SLEEP=30
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$CURRENT_DIR/.last_deploy.${PREFIX}.env"

# Get the current subscription
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

# Check if the resource group already exists
echo "Checking if [$RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_NAME] subscription..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_NAME] subscription"
	echo "Creating [$RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_NAME] subscription..."

	az group create --name $RESOURCE_GROUP_NAME --location "$LOCATION" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$RESOURCE_GROUP_NAME] resource group successfully created in the [$SUBSCRIPTION_NAME] subscription"
	else
		echo "Failed to create [$RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_NAME] subscription"
		exit 1
	fi
else
	echo "[$RESOURCE_GROUP_NAME] resource group already exists in the [$SUBSCRIPTION_NAME] subscription"
fi

# Check if the storage account already exists
echo "Checking if [$STORAGE_ACCOUNT_NAME] storage account actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$STORAGE_ACCOUNT_NAME] storage account actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$STORAGE_ACCOUNT_NAME] storage account in the [$RESOURCE_GROUP_NAME] resource group..."

	# The qrcodes container uses public 'blob' access; new storage accounts
	# disallow anonymous access unless the account explicitly allows it.
	az storage account create \
		--name $STORAGE_ACCOUNT_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--sku Standard_LRS \
		--allow-blob-public-access true 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$STORAGE_ACCOUNT_NAME] storage account successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$STORAGE_ACCOUNT_NAME] storage account in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$STORAGE_ACCOUNT_NAME] storage account already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Retrieve the storage account connection string for the data-plane bootstrap
echo "Retrieving the connection string for the [$STORAGE_ACCOUNT_NAME] storage account..."
STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query connectionString \
	--output tsv)

if [[ -n "$STORAGE_CONNECTION_STRING" ]]; then
	echo "Connection string for the [$STORAGE_ACCOUNT_NAME] storage account successfully retrieved"
else
	echo "Failed to retrieve the connection string for the [$STORAGE_ACCOUNT_NAME] storage account"
	exit 1
fi

# Create the links table
echo "Creating [$LINKS_TABLE_NAME] table in the [$STORAGE_ACCOUNT_NAME] storage account..."
az storage table create \
	--name $LINKS_TABLE_NAME \
	--connection-string "$STORAGE_CONNECTION_STRING" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "[$LINKS_TABLE_NAME] table successfully created in the [$STORAGE_ACCOUNT_NAME] storage account"
else
	echo "Failed to create [$LINKS_TABLE_NAME] table in the [$STORAGE_ACCOUNT_NAME] storage account"
	exit 1
fi

# Create the QR jobs queue
echo "Creating [$QR_JOBS_QUEUE_NAME] queue in the [$STORAGE_ACCOUNT_NAME] storage account..."
az storage queue create \
	--name $QR_JOBS_QUEUE_NAME \
	--connection-string "$STORAGE_CONNECTION_STRING" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "[$QR_JOBS_QUEUE_NAME] queue successfully created in the [$STORAGE_ACCOUNT_NAME] storage account"
else
	echo "Failed to create [$QR_JOBS_QUEUE_NAME] queue in the [$STORAGE_ACCOUNT_NAME] storage account"
	exit 1
fi

# Create the QR codes blob container with public blob access
echo "Creating [$QR_CONTAINER_NAME] container in the [$STORAGE_ACCOUNT_NAME] storage account..."
az storage container create \
	--name $QR_CONTAINER_NAME \
	--public-access blob \
	--connection-string "$STORAGE_CONNECTION_STRING" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "[$QR_CONTAINER_NAME] container successfully created in the [$STORAGE_ACCOUNT_NAME] storage account"
else
	echo "Failed to create [$QR_CONTAINER_NAME] container in the [$STORAGE_ACCOUNT_NAME] storage account"
	exit 1
fi

# Check if the user-assigned managed identity already exists
echo "Checking if [$MANAGED_IDENTITY_NAME] managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az identity show --name $MANAGED_IDENTITY_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$MANAGED_IDENTITY_NAME] managed identity actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$MANAGED_IDENTITY_NAME] managed identity in the [$RESOURCE_GROUP_NAME] resource group..."

	az identity create \
		--name $MANAGED_IDENTITY_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location "$LOCATION" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$MANAGED_IDENTITY_NAME] managed identity successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$MANAGED_IDENTITY_NAME] managed identity in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$MANAGED_IDENTITY_NAME] managed identity already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Retrieve the identity ids
IDENTITY_ID=$(az identity show --name $MANAGED_IDENTITY_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)
IDENTITY_CLIENT_ID=$(az identity show --name $MANAGED_IDENTITY_NAME --resource-group $RESOURCE_GROUP_NAME --query clientId --output tsv)
IDENTITY_PRINCIPAL_ID=$(az identity show --name $MANAGED_IDENTITY_NAME --resource-group $RESOURCE_GROUP_NAME --query principalId --output tsv)
STORAGE_ACCOUNT_ID=$(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)

# Assign the storage data-plane roles to the managed identity
for ROLE in "Storage Table Data Contributor" "Storage Queue Data Contributor" "Storage Blob Data Contributor"; do
	echo "Assigning [$ROLE] role to the [$MANAGED_IDENTITY_NAME] managed identity on the [$STORAGE_ACCOUNT_NAME] storage account..."
	# Skip when already assigned: az role assignment create is not idempotent
	# and re-runs fail with RoleAssignmentExists (Azure/azure-cli#31995).
	EXISTING_ASSIGNMENT=$(az role assignment list \
		--role "$ROLE" \
		--assignee "$IDENTITY_PRINCIPAL_ID" \
		--scope "$STORAGE_ACCOUNT_ID" \
		--query "[0].id" \
		--output tsv)
	if [[ -z "$EXISTING_ASSIGNMENT" ]]; then
		az role assignment create \
			--role "$ROLE" \
			--assignee-object-id "$IDENTITY_PRINCIPAL_ID" \
			--assignee-principal-type ServicePrincipal \
			--scope "$STORAGE_ACCOUNT_ID" 1>/dev/null
	fi

	if [[ $? == 0 ]]; then
		echo "[$ROLE] role successfully assigned to the [$MANAGED_IDENTITY_NAME] managed identity"
	else
		echo "Failed to assign [$ROLE] role to the [$MANAGED_IDENTITY_NAME] managed identity"
		exit 1
	fi
done

# Store a secret in the key vault. The value is never printed. Writes go through the Key Vault data plane, which the
# deploying principal can use only once its Key Vault Secrets Officer assignment has propagated, so a failed write is
# retried for a few minutes.
# $1: the secret name
# $2: the secret value
set_secret() {
	local secret_name=$1
	local secret_value=$2
	local attempt

	echo "Storing the [$secret_name] secret in the [$KEY_VAULT_NAME] key vault..."
	for attempt in $(seq 1 "$SECRET_RETRY_COUNT"); do
		az keyvault secret set \
			--vault-name "$KEY_VAULT_NAME" \
			--name "$secret_name" \
			--value "$secret_value" \
			--only-show-errors 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "[$secret_name] secret successfully stored in the [$KEY_VAULT_NAME] key vault"
			return 0
		fi

		if [[ $attempt -lt $SECRET_RETRY_COUNT ]]; then
			echo "Attempt $attempt of $SECRET_RETRY_COUNT to store the [$secret_name] secret failed (the [$KEY_VAULT_SECRETS_OFFICER_ROLE] assignment may still be propagating); retrying in $SECRET_RETRY_SLEEP seconds..."
			sleep "$SECRET_RETRY_SLEEP"
		fi
	done

	echo "Failed to store the [$secret_name] secret in the [$KEY_VAULT_NAME] key vault"
	exit 1
}

# Check if the key vault already exists
echo "Checking if [$KEY_VAULT_NAME] key vault actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az keyvault show --name $KEY_VAULT_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$KEY_VAULT_NAME] key vault actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$KEY_VAULT_NAME] key vault in the [$RESOURCE_GROUP_NAME] resource group..."

	az keyvault create \
		--name $KEY_VAULT_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--enable-rbac-authorization true 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$KEY_VAULT_NAME] key vault successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$KEY_VAULT_NAME] key vault in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$KEY_VAULT_NAME] key vault already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Assign the Key Vault Secrets User role to the managed identity
KEY_VAULT_ID=$(az keyvault show --name $KEY_VAULT_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)
echo "Assigning [Key Vault Secrets User] role to the [$MANAGED_IDENTITY_NAME] managed identity on the [$KEY_VAULT_NAME] key vault..."
# Skip when already assigned: az role assignment create is not idempotent
# and re-runs fail with RoleAssignmentExists (Azure/azure-cli#31995).
EXISTING_ASSIGNMENT=$(az role assignment list \
	--role "Key Vault Secrets User" \
	--assignee "$IDENTITY_PRINCIPAL_ID" \
	--scope "$KEY_VAULT_ID" \
	--query "[0].id" \
	--output tsv)
if [[ -z "$EXISTING_ASSIGNMENT" ]]; then
	az role assignment create \
		--role "Key Vault Secrets User" \
		--assignee-object-id "$IDENTITY_PRINCIPAL_ID" \
		--assignee-principal-type ServicePrincipal \
		--scope "$KEY_VAULT_ID" 1>/dev/null
fi

if [[ $? == 0 ]]; then
	echo "[Key Vault Secrets User] role successfully assigned to the [$MANAGED_IDENTITY_NAME] managed identity"
else
	echo "Failed to assign [Key Vault Secrets User] role to the [$MANAGED_IDENTITY_NAME] managed identity"
	exit 1
fi

# Resolve the object id of the deploying principal. The vault uses the RBAC permission model, so writing the secrets
# below needs the Key Vault Secrets Officer role on the vault; the script grants it to whoever runs it, a user or a
# service principal. The lookup goes through Microsoft Graph; when it fails the script continues and the role
# becomes a prerequisite (see the README).
ACCOUNT_USER_TYPE=$(az account show --query user.type --output tsv --only-show-errors)
ACCOUNT_USER_NAME=$(az account show --query user.name --output tsv --only-show-errors)

if [[ $ACCOUNT_USER_TYPE == "user" ]]; then
	DEPLOYER_PRINCIPAL_TYPE="User"
	DEPLOYER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv --only-show-errors 2>/dev/null)
else
	DEPLOYER_PRINCIPAL_TYPE="ServicePrincipal"
	DEPLOYER_OBJECT_ID=$(az ad sp show --id "$ACCOUNT_USER_NAME" --query id --output tsv --only-show-errors 2>/dev/null)
fi

# Microsoft Graph lookups need directory permissions a pipeline principal often lacks. Fall back to the oid claim of
# the CLI's own access token, which identifies the same principal without any Graph call.
if [[ -z $DEPLOYER_OBJECT_ID ]]; then
	DEPLOYER_OBJECT_ID=$(az account get-access-token --query accessToken --output tsv --only-show-errors 2>/dev/null |
		cut -d. -f2 | tr '_-' '/+' | awk '{ pad = length($0) % 4; if (pad == 2) $0 = $0 "=="; else if (pad == 3) $0 = $0 "="; print }' |
		base64 -d 2>/dev/null | jq -r '.oid // empty' 2>/dev/null)
fi

if [[ -n $DEPLOYER_OBJECT_ID ]]; then
	echo "Deploying principal [$ACCOUNT_USER_NAME] ($DEPLOYER_PRINCIPAL_TYPE) has object id [$DEPLOYER_OBJECT_ID]"
	echo "Assigning [$KEY_VAULT_SECRETS_OFFICER_ROLE] role to the deploying principal on the [$KEY_VAULT_NAME] key vault..."
	# Skip when already assigned: az role assignment create is not idempotent
	EXISTING_ASSIGNMENT=$(az role assignment list \
		--role "$KEY_VAULT_SECRETS_OFFICER_ROLE" \
		--assignee "$DEPLOYER_OBJECT_ID" \
		--scope "$KEY_VAULT_ID" \
		--query "[0].id" \
		--output tsv)
	if [[ -z "$EXISTING_ASSIGNMENT" ]]; then
		az role assignment create \
			--role "$KEY_VAULT_SECRETS_OFFICER_ROLE" \
			--assignee-object-id "$DEPLOYER_OBJECT_ID" \
			--assignee-principal-type "$DEPLOYER_PRINCIPAL_TYPE" \
			--scope "$KEY_VAULT_ID" 1>/dev/null
	fi

	if [[ $? == 0 ]]; then
		echo "[$KEY_VAULT_SECRETS_OFFICER_ROLE] role successfully assigned to the deploying principal"
	else
		echo "Failed to assign [$KEY_VAULT_SECRETS_OFFICER_ROLE] role to the deploying principal"
		exit 1
	fi
else
	echo "WARNING: could not resolve the object id of the deploying principal [$ACCOUNT_USER_NAME]; the [$KEY_VAULT_SECRETS_OFFICER_ROLE] role on the [$KEY_VAULT_NAME] key vault must already be assigned to it"
fi

# Store the link-signing key in the key vault
set_secret "$SIGN_KEY_SECRET_NAME" "$(openssl rand -hex 16)"

# Check if the PostgreSQL flexible server already exists
echo "Checking if [$POSTGRES_SERVER_NAME] PostgreSQL flexible server actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az postgres flexible-server show --name $POSTGRES_SERVER_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$POSTGRES_SERVER_NAME] PostgreSQL flexible server actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$POSTGRES_SERVER_NAME] PostgreSQL flexible server in the [$RESOURCE_GROUP_NAME] resource group..."

	POSTGRES_ADMIN_PASSWORD=$(openssl rand -hex 10)
	az postgres flexible-server create \
		--name $POSTGRES_SERVER_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--admin-user $POSTGRES_ADMIN_USER \
		--admin-password "$POSTGRES_ADMIN_PASSWORD" \
		--sku-name Standard_B1ms \
		--tier Burstable \
		--version 16 \
		--storage-size 32 \
		--public-access 0.0.0.0-255.255.255.255 \
		--yes 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$POSTGRES_SERVER_NAME] PostgreSQL flexible server successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$POSTGRES_SERVER_NAME] PostgreSQL flexible server in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$POSTGRES_SERVER_NAME] PostgreSQL flexible server already exists in the [$RESOURCE_GROUP_NAME] resource group"
	if [ -f "$STATE_FILE" ]; then
		source "$STATE_FILE"
	fi
	if [[ -z "$POSTGRES_ADMIN_PASSWORD" ]]; then
		echo "The [$POSTGRES_SERVER_NAME] server exists but its admin password is unknown; delete the server or provide POSTGRES_ADMIN_PASSWORD. Exiting."
		exit 1
	fi
fi

# Create the clicks database
echo "Creating [$POSTGRES_DB_NAME] database on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."
az postgres flexible-server db create \
	--server-name $POSTGRES_SERVER_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--name $POSTGRES_DB_NAME 1>/dev/null

if [[ $? == 0 ]]; then
	echo "[$POSTGRES_DB_NAME] database successfully created on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
else
	echo "Failed to create [$POSTGRES_DB_NAME] database on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
	exit 1
fi

# Split host:port - the LocalStack emulator embeds the dynamically allocated TCP-proxy port
# in fullyQualifiedDomainName, while real Azure returns just the bare host on 5432.
POSTGRES_FQDN=$(az postgres flexible-server show \
	--name $POSTGRES_SERVER_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query fullyQualifiedDomainName \
	--output tsv)
POSTGRES_HOST="${POSTGRES_FQDN%%:*}"
if [[ "$POSTGRES_FQDN" == *:* ]]; then
	POSTGRES_PORT="${POSTGRES_FQDN##*:}"
else
	POSTGRES_PORT=5432
fi
echo "PostgreSQL host = $POSTGRES_HOST, port = $POSTGRES_PORT"

# Persist the values that validate.sh and re-runs need; written before the app
# deployments so a late failure leaves a usable state behind.
cat >"$STATE_FILE" <<EOF
POSTGRES_ADMIN_PASSWORD=$POSTGRES_ADMIN_PASSWORD
POSTGRES_HOST=$POSTGRES_HOST
POSTGRES_PORT=$POSTGRES_PORT
EOF

# Store the PostgreSQL connection string in the key vault
set_secret "$PG_CONN_SECRET_NAME" "host=$POSTGRES_HOST port=$POSTGRES_PORT dbname=$POSTGRES_DB_NAME user=$POSTGRES_ADMIN_USER password=$POSTGRES_ADMIN_PASSWORD"

# Check if the Service Bus namespace already exists
echo "Checking if [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az servicebus namespace show --name $SERVICEBUS_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace in the [$RESOURCE_GROUP_NAME] resource group..."

	az servicebus namespace create \
		--name $SERVICEBUS_NAMESPACE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--sku Standard 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Create the link-events queue
echo "Creating [$SERVICEBUS_QUEUE_NAME] queue in the [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace..."
az servicebus queue create \
	--name $SERVICEBUS_QUEUE_NAME \
	--namespace-name $SERVICEBUS_NAMESPACE_NAME \
	--resource-group $RESOURCE_GROUP_NAME 1>/dev/null

if [[ $? == 0 ]]; then
	echo "[$SERVICEBUS_QUEUE_NAME] queue successfully created in the [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace"
else
	echo "Failed to create [$SERVICEBUS_QUEUE_NAME] queue in the [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace"
	exit 1
fi

# Assign the Service Bus data-plane roles to the managed identity
SERVICEBUS_NAMESPACE_ID=$(az servicebus namespace show --name $SERVICEBUS_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)
for ROLE in "Azure Service Bus Data Sender" "Azure Service Bus Data Receiver"; do
	echo "Assigning [$ROLE] role to the [$MANAGED_IDENTITY_NAME] managed identity on the [$SERVICEBUS_NAMESPACE_NAME] namespace..."
	# Skip when already assigned: az role assignment create is not idempotent
	# and re-runs fail with RoleAssignmentExists (Azure/azure-cli#31995).
	EXISTING_ASSIGNMENT=$(az role assignment list \
		--role "$ROLE" \
		--assignee "$IDENTITY_PRINCIPAL_ID" \
		--scope "$SERVICEBUS_NAMESPACE_ID" \
		--query "[0].id" \
		--output tsv)
	if [[ -z "$EXISTING_ASSIGNMENT" ]]; then
		az role assignment create \
			--role "$ROLE" \
			--assignee-object-id "$IDENTITY_PRINCIPAL_ID" \
			--assignee-principal-type ServicePrincipal \
			--scope "$SERVICEBUS_NAMESPACE_ID" 1>/dev/null
	fi

	if [[ $? == 0 ]]; then
		echo "[$ROLE] role successfully assigned to the [$MANAGED_IDENTITY_NAME] managed identity"
	else
		echo "Failed to assign [$ROLE] role to the [$MANAGED_IDENTITY_NAME] managed identity"
		exit 1
	fi
done

# Retrieve the Service Bus connection string used by the web app
echo "Retrieving the connection string for the [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace..."
SERVICEBUS_CONNECTION_STRING=$(az servicebus namespace authorization-rule keys list \
	--resource-group $RESOURCE_GROUP_NAME \
	--namespace-name $SERVICEBUS_NAMESPACE_NAME \
	--name RootManageSharedAccessKey \
	--query primaryConnectionString \
	--output tsv)

if [[ -n "$SERVICEBUS_CONNECTION_STRING" ]]; then
	echo "Connection string for the [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace successfully retrieved"
else
	echo "Failed to retrieve the connection string for the [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace"
	exit 1
fi

# Check if the Log Analytics workspace already exists
echo "Checking if [$LOG_ANALYTICS_NAME] Log Analytics workspace actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az monitor log-analytics workspace show --workspace-name $LOG_ANALYTICS_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$LOG_ANALYTICS_NAME] Log Analytics workspace actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$LOG_ANALYTICS_NAME] Log Analytics workspace in the [$RESOURCE_GROUP_NAME] resource group..."

	az monitor log-analytics workspace create \
		--workspace-name $LOG_ANALYTICS_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location "$LOCATION" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$LOG_ANALYTICS_NAME] Log Analytics workspace successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$LOG_ANALYTICS_NAME] Log Analytics workspace in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$LOG_ANALYTICS_NAME] Log Analytics workspace already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the Application Insights component already exists
echo "Checking if [$APPLICATION_INSIGHTS_NAME] Application Insights component exists in the [$RESOURCE_GROUP_NAME] resource group..."
az monitor app-insights component show \
	--app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APPLICATION_INSIGHTS_NAME] Application Insights component exists in the [$RESOURCE_GROUP_NAME] resource group."
	echo "Creating [$APPLICATION_INSIGHTS_NAME] Application Insights component in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create a workspace-based Application Insights component that stores the telemetry of the web app in the Log
	# Analytics workspace
	az monitor app-insights component create \
		--app "$APPLICATION_INSIGHTS_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--application-type web \
		--workspace "$LOG_ANALYTICS_NAME" \
		--tags environment=test iac=az-cli \
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

# Get the connection string of the Application Insights component
echo "Getting the connection string of the [$APPLICATION_INSIGHTS_NAME] Application Insights component..."
APPLICATION_INSIGHTS_CONNECTION_STRING=$(az monitor app-insights component show \
	--app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query connectionString \
	--output tsv \
	--only-show-errors)

if [[ -n $APPLICATION_INSIGHTS_CONNECTION_STRING ]]; then
	echo "Connection string of the [$APPLICATION_INSIGHTS_NAME] Application Insights component retrieved successfully."
else
	echo "Failed to retrieve the connection string of the [$APPLICATION_INSIGHTS_NAME] Application Insights component."
	exit 1
fi

# Get the resource ids of the storage account, of the PostgreSQL flexible server and of the Service Bus namespace
echo "Retrieving the resource ids of the storage account, of the PostgreSQL flexible server and of the Service Bus namespace..."
STORAGE_ACCOUNT_RESOURCE_ID=$(az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
POSTGRES_SERVER_ID=$(az postgres flexible-server show \
	--name "$POSTGRES_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
SERVICEBUS_NAMESPACE_ID=$(az servicebus namespace show \
	--name "$SERVICEBUS_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $STORAGE_ACCOUNT_RESOURCE_ID && -n $POSTGRES_SERVER_ID && -n $SERVICEBUS_NAMESPACE_ID && -n $LOG_ANALYTICS_ID ]]; then
	echo "Resource ids of the storage account, of the PostgreSQL flexible server and of the Service Bus namespace successfully retrieved"
else
	echo "Failed to retrieve the resource ids of the storage account, of the PostgreSQL flexible server and of the Service Bus namespace"
	exit 1
fi

# Check whether the diagnostic settings of the storage account already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$STORAGE_ACCOUNT_NAME] storage account already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$STORAGE_ACCOUNT_RESOURCE_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$STORAGE_ACCOUNT_NAME] storage account actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$STORAGE_ACCOUNT_NAME] storage account..."

	# Create the diagnostic settings that send the capacity and transaction metrics of the storage account to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$STORAGE_ACCOUNT_RESOURCE_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--metrics '[
			{"category": "Capacity", "enabled": true},
			{"category": "Transaction", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$STORAGE_ACCOUNT_NAME] storage account successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$STORAGE_ACCOUNT_NAME] storage account"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$STORAGE_ACCOUNT_NAME] storage account already exist"
fi

# The Functions host keeps its own data in the blobs, queues and tables of the storage account (AzureWebJobsStorage):
# each of the three services gets diagnostic settings that send the logs of its requests (StorageBlobLogs,
# StorageQueueLogs, StorageTableLogs) and its capacity and transaction metrics to the Log Analytics workspace
for SERVICE in blob queue table; do
	SERVICE_RESOURCE_ID="$STORAGE_ACCOUNT_RESOURCE_ID/${SERVICE}Services/default"
	echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the $SERVICE service of the [$STORAGE_ACCOUNT_NAME] storage account already exist..."
	az monitor diagnostic-settings show \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$SERVICE_RESOURCE_ID" \
		--only-show-errors &>/dev/null

	if [[ $? != 0 ]]; then
		echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the $SERVICE service of the [$STORAGE_ACCOUNT_NAME] storage account actually exist"
		echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the $SERVICE service of the [$STORAGE_ACCOUNT_NAME] storage account..."

		az monitor diagnostic-settings create \
			--name "$DIAGNOSTIC_SETTINGS_NAME" \
			--resource "$SERVICE_RESOURCE_ID" \
			--workspace "$LOG_ANALYTICS_NAME" \
			--logs '[
				{"category": "StorageRead", "enabled": true},
				{"category": "StorageWrite", "enabled": true},
				{"category": "StorageDelete", "enabled": true}
			]' \
			--metrics '[
				{"category": "Capacity", "enabled": true},
				{"category": "Transaction", "enabled": true}
			]' \
			--only-show-errors 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the $SERVICE service of the [$STORAGE_ACCOUNT_NAME] storage account successfully created"
		else
			echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the $SERVICE service of the [$STORAGE_ACCOUNT_NAME] storage account"
			exit 1
		fi
	else
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the $SERVICE service of the [$STORAGE_ACCOUNT_NAME] storage account already exist"
	fi
done

# Get the resource id of the key vault
KEY_VAULT_ID=$(az keyvault show \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -z "$KEY_VAULT_ID" ]]; then
	echo "Failed to retrieve the resource id of the [$KEY_VAULT_NAME] key vault"
	exit 1
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

	# Create the diagnostic settings for the key vault to send logs to the Log Analytics workspace, in the
	# resource-specific AZKVAuditLogs and AZKVPolicyEvaluationDetailsLogs tables rather than AzureDiagnostics
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$KEY_VAULT_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--export-to-resource-specific true \
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

# Check whether the diagnostic settings for the PostgreSQL flexible server already exist and send its logs to resource-specific tables:
# a setting an earlier version of this script created sends them to AzureDiagnostics, and the create below updates it
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server already exist..."
POSTGRES_SERVER_DESTINATION_TYPE=$(az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$POSTGRES_SERVER_ID" \
	--query logAnalyticsDestinationType \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ $POSTGRES_SERVER_DESTINATION_TYPE != "Dedicated" ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server that send its logs to resource-specific tables actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."

	# Create (or update) the diagnostic settings for the PostgreSQL flexible server to send its logs to the Log Analytics workspace, in
	# the resource-specific PGSQLServerLogs table rather than AzureDiagnostics
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$POSTGRES_SERVER_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--export-to-resource-specific true \
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

# Check whether the diagnostic settings for the service bus namespace already exist and send its logs to
# resource-specific tables: a setting an earlier version of this script created sends them to AzureDiagnostics, and the
# create below updates it
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SERVICEBUS_NAMESPACE_NAME] service bus namespace already exist..."
SERVICE_BUS_DESTINATION_TYPE=$(az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$SERVICEBUS_NAMESPACE_ID" \
	--query logAnalyticsDestinationType \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ $SERVICE_BUS_DESTINATION_TYPE != "Dedicated" ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SERVICEBUS_NAMESPACE_NAME] service bus namespace that send its logs to resource-specific tables actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SERVICEBUS_NAMESPACE_NAME] service bus namespace..."

	# Create (or update) the diagnostic settings for the service bus namespace to send its logs to the Log Analytics
	# workspace, in the resource-specific AZMS tables rather than AzureDiagnostics. The runtime audit logs are left out:
	# Service Bus writes them only in the Premium tier, and this namespace is Standard
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$SERVICEBUS_NAMESPACE_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--export-to-resource-specific true \
		--logs '[
			{"category": "OperationalLogs", "enabled": true},
			{"category": "VNetAndIPFilteringLogs", "enabled": true},
			{"category": "DiagnosticErrorLogs", "enabled": true},
			{"category": "ApplicationMetricsLogs", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SERVICEBUS_NAMESPACE_NAME] service bus namespace successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SERVICEBUS_NAMESPACE_NAME] service bus namespace"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$SERVICEBUS_NAMESPACE_NAME] service bus namespace already exist"
fi

# Check if the app service plan already exists
echo "Checking if [$APP_SERVICE_PLAN_NAME] app service plan actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az appservice plan show --name $APP_SERVICE_PLAN_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APP_SERVICE_PLAN_NAME] app service plan actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$APP_SERVICE_PLAN_NAME] app service plan in the [$RESOURCE_GROUP_NAME] resource group..."

	az appservice plan create \
		--name $APP_SERVICE_PLAN_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--sku $APP_SERVICE_PLAN_SKU \
		--is-linux 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$APP_SERVICE_PLAN_NAME] app service plan successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$APP_SERVICE_PLAN_NAME] app service plan in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$APP_SERVICE_PLAN_NAME] app service plan already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Check if the web app already exists
echo "Checking if [$WEB_APP_NAME] web app actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az webapp show --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$WEB_APP_NAME] web app actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$WEB_APP_NAME] web app in the [$RESOURCE_GROUP_NAME] resource group..."

	az webapp create \
		--name $WEB_APP_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--plan $APP_SERVICE_PLAN_NAME \
		--runtime "$RUNTIME:$WEB_APP_RUNTIME_VERSION" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$WEB_APP_NAME] web app successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$WEB_APP_NAME] web app in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$WEB_APP_NAME] web app already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Assign the managed identity to the web app
echo "Assigning the [$MANAGED_IDENTITY_NAME] managed identity to the [$WEB_APP_NAME] web app..."
az webapp identity assign \
	--name $WEB_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--identities "$IDENTITY_ID" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "[$MANAGED_IDENTITY_NAME] managed identity successfully assigned to the [$WEB_APP_NAME] web app"
else
	echo "Failed to assign the [$MANAGED_IDENTITY_NAME] managed identity to the [$WEB_APP_NAME] web app"
	exit 1
fi

# Retrieve the storage endpoints for the app settings
TABLES_ENDPOINT=$(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME --query primaryEndpoints.table --output tsv)
QUEUE_ENDPOINT=$(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME --query primaryEndpoints.queue --output tsv)
BLOB_ENDPOINT=$(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME --query primaryEndpoints.blob --output tsv)
KEYVAULT_URL=$(az keyvault show --name $KEY_VAULT_NAME --resource-group $RESOURCE_GROUP_NAME --query properties.vaultUri --output tsv)
INTERNAL_TOKEN=$(openssl rand -hex 12)

# Configure the web app settings
echo "Setting app settings for the [$WEB_APP_NAME] web app..."
az webapp config appsettings set \
	--name $WEB_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	AZURE_CLIENT_ID="$IDENTITY_CLIENT_ID" \
	AZURE_TABLES_ENDPOINT="$TABLES_ENDPOINT" \
	LINKS_TABLE="$LINKS_TABLE_NAME" \
	KEYVAULT_URL="$KEYVAULT_URL" \
	QUEUE_ENDPOINT="$QUEUE_ENDPOINT" \
	QR_JOBS_QUEUE="$QR_JOBS_QUEUE_NAME" \
	BLOB_ENDPOINT="$BLOB_ENDPOINT" \
	QR_CONTAINER="$QR_CONTAINER_NAME" \
	SB_CONN="$SERVICEBUS_CONNECTION_STRING" \
	SB_QUEUE="$SERVICEBUS_QUEUE_NAME" \
	PG_SECRET_NAME="$PG_CONN_SECRET_NAME" \
	APPLICATIONINSIGHTS_CONNECTION_STRING="$APPLICATION_INSIGHTS_CONNECTION_STRING" \
	INTERNAL_TOKEN="$INTERNAL_TOKEN" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "App settings for the [$WEB_APP_NAME] web app successfully set"
else
	echo "Failed to set app settings for the [$WEB_APP_NAME] web app"
	exit 1
fi

# Get the resource ids of the web app and of its App Service plan
WEB_APP_ID=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
APP_SERVICE_PLAN_ID=$(az appservice plan show \
	--name "$APP_SERVICE_PLAN_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -z $WEB_APP_ID || -z $APP_SERVICE_PLAN_ID ]]; then
	echo "Failed to retrieve the resource ids of the [$WEB_APP_NAME] web app and of its App Service plan"
	exit 1
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

	# Create the diagnostic settings for the web app to send its logs and metrics to the Log Analytics workspace
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

# Check whether the diagnostic settings for the App Service plan already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$APP_SERVICE_PLAN_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan..."

	# Create the diagnostic settings for the App Service plan to send its metrics to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$APP_SERVICE_PLAN_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan already exist"
fi

# Create the zip package of the web app
cd "$CURRENT_DIR/../src" || exit
if [ -f "$WEBAPP_ZIPFILE" ]; then
	rm "$WEBAPP_ZIPFILE"
fi
echo "Creating zip package of the web app..."
zip -r "$WEBAPP_ZIPFILE" app.py gunicorn.conf.py requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$WEBAPP_ZIPFILE]..."
az webapp deploy \
	--resource-group $RESOURCE_GROUP_NAME \
	--name $WEB_APP_NAME \
	--src-path "$WEBAPP_ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [[ $? == 0 ]]; then
	echo "Web app [$WEB_APP_NAME] deployed successfully"
else
	echo "Failed to deploy web app [$WEB_APP_NAME]"
	exit 1
fi
rm -f "$WEBAPP_ZIPFILE"

WEB_APP_HOSTNAME=$(az webapp show --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query defaultHostName --output tsv)

# Check if the function app already exists
echo "Checking if [$FUNCTION_APP_NAME] function app actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az functionapp show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$FUNCTION_APP_NAME] function app actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$FUNCTION_APP_NAME] function app in the [$RESOURCE_GROUP_NAME] resource group..."

	az functionapp create \
		--name $FUNCTION_APP_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--plan $APP_SERVICE_PLAN_NAME \
		--storage-account $STORAGE_ACCOUNT_NAME \
		--runtime $RUNTIME \
		--runtime-version 3.11 \
		--functions-version $FUNCTIONS_VERSION \
		--app-insights "$APPLICATION_INSIGHTS_NAME" \
		--os-type Linux 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$FUNCTION_APP_NAME] function app successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$FUNCTION_APP_NAME] function app in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$FUNCTION_APP_NAME] function app already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Assign the managed identity to the function app
echo "Assigning the [$MANAGED_IDENTITY_NAME] managed identity to the [$FUNCTION_APP_NAME] function app..."
az functionapp identity assign \
	--name $FUNCTION_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--identities "$IDENTITY_ID" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "[$MANAGED_IDENTITY_NAME] managed identity successfully assigned to the [$FUNCTION_APP_NAME] function app"
else
	echo "Failed to assign the [$MANAGED_IDENTITY_NAME] managed identity to the [$FUNCTION_APP_NAME] function app"
	exit 1
fi

# Configure the function app settings: the Service Bus trigger binds with the managed
# identity (FQNS + client id), the queue trigger uses an explicit-endpoints connection
# string, and the worker calls back into the web app's internal API.
STORAGE_ACCOUNT_KEY=$(az storage account keys list --account-name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME --query "[0].value" --output tsv)
echo "Setting app settings for the [$FUNCTION_APP_NAME] function app..."
az functionapp config appsettings set \
	--name $FUNCTION_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	FUNCTIONS_WORKER_RUNTIME="$RUNTIME" \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	AZURE_CLIENT_ID="$IDENTITY_CLIENT_ID" \
	ServiceBusConnection__fullyQualifiedNamespace="${SERVICEBUS_NAMESPACE_NAME}.servicebus.windows.net" \
	ServiceBusConnection__clientId="$IDENTITY_CLIENT_ID" \
	ServiceBusConnection__credential="managedidentity" \
	QrStorage="DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_ACCOUNT_KEY};BlobEndpoint=${BLOB_ENDPOINT};QueueEndpoint=${QUEUE_ENDPOINT};TableEndpoint=${TABLES_ENDPOINT}" \
	WEB_BASE_URL="http://$WEB_APP_HOSTNAME" \
	APPLICATIONINSIGHTS_CONNECTION_STRING="$APPLICATION_INSIGHTS_CONNECTION_STRING" \
	PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY='true' \
	PYTHON_APPLICATIONINSIGHTS_LOGGER_NAME='function_app' \
	INTERNAL_TOKEN="$INTERNAL_TOKEN" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "App settings for the [$FUNCTION_APP_NAME] function app successfully set"
else
	echo "Failed to set app settings for the [$FUNCTION_APP_NAME] function app"
	exit 1
fi

# Get the resource id of the function app
echo "Retrieving the resource id of the [$FUNCTION_APP_NAME] function app..."
FUNCTION_APP_ID=$(az functionapp show \
	--name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $FUNCTION_APP_ID ]]; then
	echo "Resource id [$FUNCTION_APP_ID] of the [$FUNCTION_APP_NAME] function app successfully retrieved"
else
	echo "Failed to retrieve the resource id of the [$FUNCTION_APP_NAME] function app"
	exit 1
fi

# Check whether the diagnostic settings of the function app already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_NAME] function app already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$FUNCTION_APP_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_NAME] function app actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$FUNCTION_APP_NAME] function app..."

	# Create the diagnostic settings that send the logs of the Functions host and of the functions (FunctionAppLogs)
	# and the platform metrics of the function app to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$FUNCTION_APP_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "FunctionAppLogs", "enabled": true}
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

# Check whether the diagnostic settings for the Log Analytics workspace already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$LOG_ANALYTICS_NAME] Log Analytics workspace already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$LOG_ANALYTICS_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$LOG_ANALYTICS_NAME] Log Analytics workspace actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$LOG_ANALYTICS_NAME] Log Analytics workspace..."

	# Create the diagnostic settings that send the audit records of the queries run on the workspace (LAQueryLogs) and its platform metrics to the workspace itself
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$LOG_ANALYTICS_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "Audit", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$LOG_ANALYTICS_NAME] Log Analytics workspace successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$LOG_ANALYTICS_NAME] Log Analytics workspace"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$LOG_ANALYTICS_NAME] Log Analytics workspace already exist"
fi

# Create the zip package of the function app
cd "$CURRENT_DIR/../function" || exit
if [ -f "$WORKER_ZIPFILE" ]; then
	rm "$WORKER_ZIPFILE"
fi
echo "Creating zip package of the function app..."
zip -r "$WORKER_ZIPFILE" function_app.py host.json requirements.txt

# Deploy the function app
echo "Deploying function app [$FUNCTION_APP_NAME] with zip file [$WORKER_ZIPFILE]..."
# On Azure the first deployment to a new function app can time out (504) while its deployment site starts, so a failed
# attempt is retried
DEPLOYED=0
for ((ATTEMPT = 1; ATTEMPT <= DEPLOY_RETRY_COUNT; ATTEMPT++)); do
	az functionapp deploy \
		--resource-group $RESOURCE_GROUP_NAME \
		--name $FUNCTION_APP_NAME \
		--src-path "$WORKER_ZIPFILE" \
		--type zip \
		--async true 1>/dev/null

	if [[ $? == 0 ]]; then
		DEPLOYED=1
		break
	fi

	if [[ $ATTEMPT -lt $DEPLOY_RETRY_COUNT ]]; then
		echo "Attempt $ATTEMPT of $DEPLOY_RETRY_COUNT to deploy function app [$FUNCTION_APP_NAME] failed. Waiting [$DEPLOY_RETRY_SLEEP] seconds before retry..."
		sleep $DEPLOY_RETRY_SLEEP
	fi
done

if [[ $DEPLOYED == 1 ]]; then
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully"
else
	echo "Failed to deploy function app [$FUNCTION_APP_NAME]"
	exit 1
fi
rm -f "$WORKER_ZIPFILE"

echo "Deployment completed. Web app available at: http://$WEB_APP_HOSTNAME"
