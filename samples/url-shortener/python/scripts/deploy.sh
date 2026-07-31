#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}msastorage${SUFFIX}"
LINKS_TABLE_NAME='links'
QR_JOBS_QUEUE_NAME='qrjobs'
QR_CONTAINER_NAME='qrcodes'
MANAGED_IDENTITY_NAME="${PREFIX}-msa-identity-${SUFFIX}"
KEY_VAULT_NAME="${PREFIX}-msa-kv-${SUFFIX}"
SIGN_KEY_SECRET_NAME='link-sign-key'
PG_CONN_SECRET_NAME='pg-conn'
POSTGRES_SERVER_NAME="${PREFIX}-msa-pgflex-${SUFFIX}"
POSTGRES_ADMIN_USER='linkletadmin'
POSTGRES_DB_NAME='clicks'
SERVICEBUS_NAMESPACE_NAME="${PREFIX}-msa-sb-ns-${SUFFIX}"
SERVICEBUS_QUEUE_NAME='link-events'
LOG_ANALYTICS_NAME="${PREFIX}-msa-log-analytics-${SUFFIX}"
APP_SERVICE_PLAN_NAME="${PREFIX}-msa-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU='B1'
WEB_APP_NAME="${PREFIX}-msa-webapp-${SUFFIX}"
FUNCTION_APP_NAME="${PREFIX}-msa-functionapp-${SUFFIX}"
RUNTIME='python'
WEB_APP_RUNTIME_VERSION='3.13'
FUNCTIONS_VERSION='4'
WEBAPP_ZIPFILE='linklet_webapp.zip'
WORKER_ZIPFILE='linklet_worker.zip'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$CURRENT_DIR/.last_deploy.env"

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

	az storage account create \
		--name $STORAGE_ACCOUNT_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--sku Standard_LRS 1>/dev/null

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
	az role assignment create \
		--role "$ROLE" \
		--assignee-object-id "$IDENTITY_PRINCIPAL_ID" \
		--assignee-principal-type ServicePrincipal \
		--scope "$STORAGE_ACCOUNT_ID" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$ROLE] role successfully assigned to the [$MANAGED_IDENTITY_NAME] managed identity"
	else
		echo "Failed to assign [$ROLE] role to the [$MANAGED_IDENTITY_NAME] managed identity"
		exit 1
	fi
done

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
az role assignment create \
	--role "Key Vault Secrets User" \
	--assignee-object-id "$IDENTITY_PRINCIPAL_ID" \
	--assignee-principal-type ServicePrincipal \
	--scope "$KEY_VAULT_ID" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "[Key Vault Secrets User] role successfully assigned to the [$MANAGED_IDENTITY_NAME] managed identity"
else
	echo "Failed to assign [Key Vault Secrets User] role to the [$MANAGED_IDENTITY_NAME] managed identity"
	exit 1
fi

# Store the link-signing key in the key vault
echo "Storing the [$SIGN_KEY_SECRET_NAME] secret in the [$KEY_VAULT_NAME] key vault..."
SIGN_KEY=$(openssl rand -hex 16)
az keyvault secret set \
	--vault-name $KEY_VAULT_NAME \
	--name $SIGN_KEY_SECRET_NAME \
	--value "$SIGN_KEY" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "[$SIGN_KEY_SECRET_NAME] secret successfully stored in the [$KEY_VAULT_NAME] key vault"
else
	echo "Failed to store the [$SIGN_KEY_SECRET_NAME] secret in the [$KEY_VAULT_NAME] key vault"
	exit 1
fi

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
echo "Storing the [$PG_CONN_SECRET_NAME] secret in the [$KEY_VAULT_NAME] key vault..."
az keyvault secret set \
	--vault-name $KEY_VAULT_NAME \
	--name $PG_CONN_SECRET_NAME \
	--value "host=$POSTGRES_HOST port=$POSTGRES_PORT dbname=$POSTGRES_DB_NAME user=$POSTGRES_ADMIN_USER password=$POSTGRES_ADMIN_PASSWORD" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "[$PG_CONN_SECRET_NAME] secret successfully stored in the [$KEY_VAULT_NAME] key vault"
else
	echo "Failed to store the [$PG_CONN_SECRET_NAME] secret in the [$KEY_VAULT_NAME] key vault"
	exit 1
fi

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
	az role assignment create \
		--role "$ROLE" \
		--assignee-object-id "$IDENTITY_PRINCIPAL_ID" \
		--assignee-principal-type ServicePrincipal \
		--scope "$SERVICEBUS_NAMESPACE_ID" 1>/dev/null

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

# Attach diagnostic settings for the storage account to the Log Analytics workspace
echo "Attaching diagnostic settings for the [$STORAGE_ACCOUNT_NAME] storage account to the [$LOG_ANALYTICS_NAME] workspace..."
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show --workspace-name $LOG_ANALYTICS_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)
az monitor diagnostic-settings create \
	--name default \
	--resource "$STORAGE_ACCOUNT_ID" \
	--workspace "$LOG_ANALYTICS_ID" \
	--metrics '[{"category":"Transaction","enabled":true}]' \
	--output none

if [[ $? == 0 ]]; then
	echo "Diagnostic settings successfully attached to the [$STORAGE_ACCOUNT_NAME] storage account"
else
	echo "Failed to attach diagnostic settings to the [$STORAGE_ACCOUNT_NAME] storage account"
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
	INTERNAL_TOKEN="$INTERNAL_TOKEN" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "App settings for the [$WEB_APP_NAME] web app successfully set"
else
	echo "Failed to set app settings for the [$WEB_APP_NAME] web app"
	exit 1
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
	AZURE_CLIENT_ID="$IDENTITY_CLIENT_ID" \
	ServiceBusConnection__fullyQualifiedNamespace="${SERVICEBUS_NAMESPACE_NAME}.servicebus.windows.net" \
	ServiceBusConnection__clientId="$IDENTITY_CLIENT_ID" \
	ServiceBusConnection__credential="managedidentity" \
	QrStorage="DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_ACCOUNT_KEY};BlobEndpoint=${BLOB_ENDPOINT};QueueEndpoint=${QUEUE_ENDPOINT};TableEndpoint=${TABLES_ENDPOINT}" \
	WEB_BASE_URL="http://$WEB_APP_HOSTNAME" \
	INTERNAL_TOKEN="$INTERNAL_TOKEN" 1>/dev/null

if [[ $? == 0 ]]; then
	echo "App settings for the [$FUNCTION_APP_NAME] function app successfully set"
else
	echo "Failed to set app settings for the [$FUNCTION_APP_NAME] function app"
	exit 1
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
az functionapp deploy \
	--resource-group $RESOURCE_GROUP_NAME \
	--name $FUNCTION_APP_NAME \
	--src-path "$WORKER_ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [[ $? == 0 ]]; then
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully"
else
	echo "Failed to deploy function app [$FUNCTION_APP_NAME]"
	exit 1
fi
rm -f "$WORKER_ZIPFILE"

echo "Deployment completed. Web app available at: http://$WEB_APP_HOSTNAME"
