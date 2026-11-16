#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="B1"
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
RUNTIME="dotnetcore"
RUNTIME_VERSION="10.0"
CONTAINER_NAME='activities'
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-insights-${SUFFIX}"
DIAGNOSTIC_SETTINGS_NAME="default"
ZIPFILE="webapp_app.zip"
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
RETRY_COUNT=3
SLEEP=5

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
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created in the subscription [$SUBSCRIPTION_NAME]"
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]"
		exit 1
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists in the subscription [$SUBSCRIPTION_NAME]"
fi

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
		--location "$LOCATION" \
		--resource-group $RESOURCE_GROUP_NAME \
		--sku Standard_LRS 1>/dev/null

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
	echo "Storage account key retrieved successfully."
else
	echo "Failed to retrieve storage account key."
	exit 1
fi

# Get the storage account resource ID
STORAGE_ACCOUNT_RESOURCE_ID=$(az storage account show \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "id" \
	--output tsv \
	--only-show-errors)

if [ -n "$STORAGE_ACCOUNT_RESOURCE_ID" ]; then
	echo "Storage account resource ID retrieved successfully: $STORAGE_ACCOUNT_RESOURCE_ID"
else
	echo "Failed to retrieve storage account resource ID."
	exit 1
fi

# Get the storage account blob primary endpoint
AZURE_STORAGE_ACCOUNT_URL=$(az storage account show \
	--name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "primaryEndpoints.blob" \
	--output tsv \
	--only-show-errors)

if [ -n "$AZURE_STORAGE_ACCOUNT_URL" ]; then
	echo "Storage account blob primary endpoint retrieved successfully: $AZURE_STORAGE_ACCOUNT_URL"
else
	echo "Failed to retrieve storage account blob primary endpoint."
	exit 1
fi

# Create blob container
echo "Creating blob container [$CONTAINER_NAME] in the [$STORAGE_ACCOUNT_NAME] storage account..."
az storage container create \
	--name $CONTAINER_NAME \
	--account-name $STORAGE_ACCOUNT_NAME \
	--account-key "$STORAGE_ACCOUNT_KEY" \
	--public-access off 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Blob container [$CONTAINER_NAME] created successfully in the [$STORAGE_ACCOUNT_NAME] storage account."
else
	echo "Failed to create blob container [$CONTAINER_NAME] in the [$STORAGE_ACCOUNT_NAME] storage account."
	exit 1
fi

# Check if the Log Analytics workspace already exists
echo "Checking if [$LOG_ANALYTICS_NAME] Log Analytics workspace exists in the [$RESOURCE_GROUP_NAME] resource group..."
az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$LOG_ANALYTICS_NAME] Log Analytics workspace exists in the [$RESOURCE_GROUP_NAME] resource group."
	echo "Creating [$LOG_ANALYTICS_NAME] Log Analytics workspace in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the Log Analytics workspace that the Application Insights component sends its telemetry to
	az monitor log-analytics workspace create \
		--name "$LOG_ANALYTICS_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$LOG_ANALYTICS_NAME] Log Analytics workspace created successfully in the [$RESOURCE_GROUP_NAME] resource group."
	else
		echo "Failed to create [$LOG_ANALYTICS_NAME] Log Analytics workspace in the [$RESOURCE_GROUP_NAME] resource group."
		exit 1
	fi
else
	echo "[$LOG_ANALYTICS_NAME] Log Analytics workspace already exists in the [$RESOURCE_GROUP_NAME] resource group."
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

	# Create a workspace-based Application Insights component that sends its data to the Log Analytics workspace
	az monitor app-insights component create \
		--app "$APPLICATION_INSIGHTS_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--application-type web \
		--workspace "$LOG_ANALYTICS_NAME" \
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

# Check if the App Service Plan already exists
echo "Checking if App Service Plan [$APP_SERVICE_PLAN_NAME] exists in the resource group [$RESOURCE_GROUP_NAME]..."
az appservice plan show \
	--name $APP_SERVICE_PLAN_NAME \
	--resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No App Service Plan [$APP_SERVICE_PLAN_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group."
	# Create App Service Plan
	echo "Creating App Service Plan [$APP_SERVICE_PLAN_NAME]..."
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
	echo "App Service Plan [$APP_SERVICE_PLAN_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group."
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

# Check if the web app already exists
echo "Checking if web app [$WEB_APP_NAME] exists in the resource group [$RESOURCE_GROUP_NAME]..."
az webapp show \
	--name $WEB_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No web app [$WEB_APP_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group."
	# Create the web app
	echo "Creating web app [$WEB_APP_NAME]..."
	az webapp create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--plan "$APP_SERVICE_PLAN_NAME" \
		--name "$WEB_APP_NAME" \
		--runtime "$RUNTIME:$RUNTIME_VERSION" \
		--assign-identity "${IDENTITY_ID}" \
		--only-show-errors 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Web app [$WEB_APP_NAME] created successfully."
	else
		echo "Failed to create web app [$WEB_APP_NAME]."
		exit 1
	fi
else
	echo "Web app [$WEB_APP_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group."
fi

# Assign the Storage Blob Data Contributor role to the managed identity with the storage account as scope
ROLE="Storage Blob Data Contributor"
echo "Checking if the managed identity with principal ID [$PRINCIPAL_ID] has the [$ROLE] role assignment on storage account [$STORAGE_ACCOUNT_NAME]..."
current=$(az role assignment list \
	--assignee "$PRINCIPAL_ID" \
	--scope "$STORAGE_ACCOUNT_RESOURCE_ID" \
	--query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
	--output tsv 2>/dev/null)

if [[ $current == $ROLE ]]; then
	echo "Managed identity already has the [$ROLE] role assignment on storage account [$STORAGE_ACCOUNT_NAME]"
else
	echo "Managed identity does not have the [$ROLE] role assignment on storage account [$STORAGE_ACCOUNT_NAME]"
	echo "Creating role assignment: assigning [$ROLE] role to managed identity on storage account [$STORAGE_ACCOUNT_NAME]..."
	ATTEMPT=1
	ASSIGNED=0
	while [ $ATTEMPT -le $RETRY_COUNT ]; do
		echo "Attempt $ATTEMPT of $RETRY_COUNT to assign role..."
		az role assignment create \
			--assignee-object-id "$PRINCIPAL_ID" \
			--assignee-principal-type ServicePrincipal \
			--role "$ROLE" \
			--scope "$STORAGE_ACCOUNT_RESOURCE_ID" 1>/dev/null

		if [[ $? == 0 ]]; then
			ASSIGNED=1
			break
		else
			if [ $ATTEMPT -lt $RETRY_COUNT ]; then
				echo "Role assignment failed. Waiting [$SLEEP] seconds before retry..."
				sleep $SLEEP
			fi
			ATTEMPT=$((ATTEMPT + 1))
		fi
	done

	if [[ $ASSIGNED == 1 ]]; then
		echo "Successfully assigned [$ROLE] role to managed identity on storage account [$STORAGE_ACCOUNT_NAME]"
	else
		echo "Failed to assign [$ROLE] role to managed identity on storage account [$STORAGE_ACCOUNT_NAME]"
		exit 1
	fi
fi

# Set web app settings
echo "Setting web app settings for [$WEB_APP_NAME]..."
az webapp config appsettings set \
	--name $WEB_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	AZURE_CLIENT_ID="$CLIENT_ID" \
	AZURE_STORAGE_ACCOUNT_URL="$AZURE_STORAGE_ACCOUNT_URL" \
	CONTAINER_NAME="$CONTAINER_NAME" \
	APPLICATIONINSIGHTS_CONNECTION_STRING="$APPLICATION_INSIGHTS_CONNECTION_STRING" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app settings for [$WEB_APP_NAME] set successfully."
else
	echo "Failed to set web app settings for [$WEB_APP_NAME]."
	exit 1
fi

# Get the resource id of the web app
echo "Retrieving the resource id of the [$WEB_APP_NAME] web app..."
WEB_APP_ID=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $WEB_APP_ID ]]; then
	echo "Resource id [$WEB_APP_ID] of the [$WEB_APP_NAME] web app successfully retrieved"
else
	echo "Failed to retrieve the resource id of the [$WEB_APP_NAME] web app"
	exit 1
fi

# Get the resource id of the App Service plan
echo "Retrieving the resource id of the [$APP_SERVICE_PLAN_NAME] App Service plan..."
APP_SERVICE_PLAN_ID=$(az appservice plan show \
	--name "$APP_SERVICE_PLAN_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $APP_SERVICE_PLAN_ID ]]; then
	echo "Resource id [$APP_SERVICE_PLAN_ID] of the [$APP_SERVICE_PLAN_NAME] App Service plan successfully retrieved"
else
	echo "Failed to retrieve the resource id of the [$APP_SERVICE_PLAN_NAME] App Service plan"
	exit 1
fi

# Check whether the diagnostic settings of the web app already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$WEB_APP_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$WEB_APP_NAME] web app..."

	# Create the diagnostic settings that send the logs and the platform metrics of the web app to the Log Analytics workspace
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

# Check whether the diagnostic settings of the App Service plan already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$APP_SERVICE_PLAN_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$APP_SERVICE_PLAN_NAME] App Service plan..."

	# Create the diagnostic settings that send the platform metrics of the App Service plan to the Log Analytics workspace
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

# Get the resource id of the Log Analytics workspace
echo "Retrieving the resource id of the [$LOG_ANALYTICS_NAME] Log Analytics workspace..."
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $LOG_ANALYTICS_ID ]]; then
	echo "Resource id [$LOG_ANALYTICS_ID] of the [$LOG_ANALYTICS_NAME] Log Analytics workspace successfully retrieved"
else
	echo "Failed to retrieve the resource id of the [$LOG_ANALYTICS_NAME] Log Analytics workspace"
	exit 1
fi

# Check whether the diagnostic settings of the Log Analytics workspace already exist
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

# Check whether the diagnostic settings of the storage account already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$STORAGE_ACCOUNT_NAME] storage account already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$STORAGE_ACCOUNT_RESOURCE_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$STORAGE_ACCOUNT_NAME] storage account actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$STORAGE_ACCOUNT_NAME] storage account..."

	# Create the diagnostic settings that send the transaction metrics of the storage account to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$STORAGE_ACCOUNT_RESOURCE_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--metrics '[
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

# Check whether the diagnostic settings of the blob service of the storage account already exist
BLOB_SERVICE_RESOURCE_ID="$STORAGE_ACCOUNT_RESOURCE_ID/blobServices/default"
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the blob service of the [$STORAGE_ACCOUNT_NAME] storage account already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$BLOB_SERVICE_RESOURCE_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the blob service of the [$STORAGE_ACCOUNT_NAME] storage account actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the blob service of the [$STORAGE_ACCOUNT_NAME] storage account..."

	# Create the diagnostic settings that send the logs of the requests to the blobs (StorageBlobLogs) and the transaction metrics of the blob service to the Log Analytics workspace
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$BLOB_SERVICE_RESOURCE_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "StorageRead", "enabled": true},
			{"category": "StorageWrite", "enabled": true},
			{"category": "StorageDelete", "enabled": true}
		]' \
		--metrics '[
			{"category": "Transaction", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the blob service of the [$STORAGE_ACCOUNT_NAME] storage account successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the blob service of the [$STORAGE_ACCOUNT_NAME] storage account"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the blob service of the [$STORAGE_ACCOUNT_NAME] storage account already exist"
fi

# CD into the web app directory
cd ../src || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" . -x "bin/*" "obj/*" "publish/*" "*.zip"

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
az webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app [$WEB_APP_NAME] created successfully."
else
	echo "Failed to create web app [$WEB_APP_NAME]."
	exit 1
fi

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi
