#!/bin/bash

# Variables
# Overridable so the same scripts can deploy to real Azure, where the API Management service, the
# storage account and the Function App all need globally unique names:
#   PREFIX=apimdemo SUFFIX=$RANDOM bash scripts/deploy.sh
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}invstorage${SUFFIX}"
APP_SERVICE_PLAN_NAME="${PREFIX}-inventory-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU='B1'
FUNCTION_APP_NAME="${PREFIX}-inventory-functionapp-${SUFFIX}"
RUNTIME='python'
RUNTIME_VERSION='3.11'
FUNCTIONS_VERSION='4'
APIM_NAME="${PREFIX}-inventory-apim-${SUFFIX}"
APIM_SKU='Consumption'
APIM_PUBLISHER_NAME='LocalStack'
APIM_PUBLISHER_EMAIL='noreply@localstack.cloud'
APIM_API_VERSION='2022-08-01'
API_ID='inventory-api'
API_DISPLAY_NAME='Inventory API'
API_PATH='inventory'
PRODUCT_ID='inventory-partners'
PRODUCT_NAME='Inventory Partners'
APIM_SUBSCRIPTION_ID='partner-subscription'
NAMED_VALUE_ID='backend-secret'
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-insights-${SUFFIX}"
DIAGNOSTIC_SETTINGS_NAME='default'
FUNCTION_ZIPFILE='inventory_function.zip'
DEPLOY_RETRY_COUNT=3
DEPLOY_RETRY_SLEEP=30
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# On Windows, Git Bash and MSYS2 shells pass a path such as /tmp/... unconverted to Windows programs
# (az, curl, jq, python, docker) when MSYS_NO_PATHCONV=1 is set, as the README asks. cygpath, which
# those shells provide, returns the C:/... form those programs can open; elsewhere the path is unchanged.
native_path() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -m "$1"
	else
		echo "$1"
	fi
}

APIM_DIR="$(native_path "$CURRENT_DIR/../apim")"

# Get the current subscription
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

# The emulator's Function App answers on plain HTTP under its own hostname, while real Azure
# serves *.azurewebsites.net over HTTPS. Everything else below is the same on both.
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	BACKEND_SCHEME='http'
else
	BACKEND_SCHEME='https'
fi

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

# Check if the Log Analytics workspace already exists
echo "Checking if [$LOG_ANALYTICS_NAME] Log Analytics workspace already exists in the [$RESOURCE_GROUP_NAME] resource group..."
az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$LOG_ANALYTICS_NAME] Log Analytics workspace actually exists in the [$RESOURCE_GROUP_NAME] resource group"
	echo "Creating [$LOG_ANALYTICS_NAME] Log Analytics workspace in the [$RESOURCE_GROUP_NAME] resource group..."

	# Create the Log Analytics workspace that receives the telemetry of Application Insights and the logs and metrics
	# of the diagnostic settings
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

# Get the resource id of the Log Analytics workspace
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -z $LOG_ANALYTICS_ID ]]; then
	echo "Failed to retrieve the resource id of the [$LOG_ANALYTICS_NAME] Log Analytics workspace"
	exit 1
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
		--runtime-version $RUNTIME_VERSION \
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

# Check if the API Management service already exists
echo "Checking if [$APIM_NAME] API Management service actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APIM_NAME] API Management service actually exists in the [$RESOURCE_GROUP_NAME] resource group"

	# A deleted instance is soft-deleted and keeps its name reserved until it is purged, so an
	# earlier run's instance would make the create below fail with a conflict. Purge it first.
	az apim deletedservice show --service-name $APIM_NAME --location "$LOCATION" &>/dev/null

	if [[ $? == 0 ]]; then
		echo "Purging the soft-deleted [$APIM_NAME] API Management service that still holds the name..."
		az apim deletedservice purge --service-name $APIM_NAME --location "$LOCATION" 1>/dev/null

		if [[ $? == 0 ]]; then
			echo "Soft-deleted [$APIM_NAME] API Management service successfully purged"
		else
			echo "Failed to purge the soft-deleted [$APIM_NAME] API Management service"
			exit 1
		fi
	fi

	echo "Creating [$APIM_NAME] API Management service in the [$RESOURCE_GROUP_NAME] resource group..."

	# The Consumption tier provisions in minutes on Azure; the classic tiers take the better
	# part of an hour.
	az apim create \
		--name $APIM_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--location "$LOCATION" \
		--sku-name $APIM_SKU \
		--publisher-name "$APIM_PUBLISHER_NAME" \
		--publisher-email "$APIM_PUBLISHER_EMAIL" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$APIM_NAME] API Management service successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$APIM_NAME] API Management service in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$APIM_NAME] API Management service already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

APIM_ID=$(az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)

# The shared secret the gateway adds to every backend call lives in a secret named value, so the
# policy document refers to it as {{backend-secret}} and never contains it. A re-run reuses the
# stored value, which keeps the gateway and the Function App in agreement.
echo "Checking if [$NAMED_VALUE_ID] named value actually exists in the [$APIM_NAME] API Management service..."
az apim nv show --named-value-id $NAMED_VALUE_ID --service-name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$NAMED_VALUE_ID] named value actually exists in the [$APIM_NAME] API Management service"
	echo "Creating [$NAMED_VALUE_ID] named value in the [$APIM_NAME] API Management service..."
	BACKEND_SECRET=$(openssl rand -hex 16)

	az apim nv create \
		--named-value-id $NAMED_VALUE_ID \
		--display-name $NAMED_VALUE_ID \
		--service-name $APIM_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--secret true \
		--value "$BACKEND_SECRET" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$NAMED_VALUE_ID] named value successfully created in the [$APIM_NAME] API Management service"
	else
		echo "Failed to create [$NAMED_VALUE_ID] named value in the [$APIM_NAME] API Management service"
		exit 1
	fi
else
	echo "[$NAMED_VALUE_ID] named value already exists in the [$APIM_NAME] API Management service"
	BACKEND_SECRET=$(az apim nv show-secret \
		--named-value-id $NAMED_VALUE_ID \
		--service-name $APIM_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--query value \
		--output tsv)

	if [[ -z "$BACKEND_SECRET" ]]; then
		echo "Failed to read the [$NAMED_VALUE_ID] named value from the [$APIM_NAME] API Management service"
		exit 1
	fi
fi

# The Functions host keeps its locks and keys in the storage account. az functionapp create builds AzureWebJobsStorage
# from the storage endpoint suffix of the current cloud, which carries a port on the emulator that the host can't
# parse, so the setting is written again with the core.windows.net suffix, as on Azure
echo "Getting the key of the [$STORAGE_ACCOUNT_NAME] storage account..."
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
	--account-name $STORAGE_ACCOUNT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "[0].value" \
	--output tsv \
	--only-show-errors)

if [[ -z $STORAGE_ACCOUNT_KEY ]]; then
	echo "Failed to get the key of the [$STORAGE_ACCOUNT_NAME] storage account"
	exit 1
fi

# Configure the function app settings: the same secret the gateway injects
echo "Setting app settings for the [$FUNCTION_APP_NAME] function app..."
az functionapp config appsettings set \
	--name $FUNCTION_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	AzureWebJobsStorage="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT_NAME;AccountKey=$STORAGE_ACCOUNT_KEY;EndpointSuffix=core.windows.net" \
	FUNCTIONS_WORKER_RUNTIME="$RUNTIME" \
	SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	BACKEND_SECRET="$BACKEND_SECRET" \
	APPLICATIONINSIGHTS_CONNECTION_STRING="$APPLICATION_INSIGHTS_CONNECTION_STRING" \
	PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY='true' \
	PYTHON_APPLICATIONINSIGHTS_LOGGER_NAME='function_app' 1>/dev/null

if [[ $? == 0 ]]; then
	echo "App settings for the [$FUNCTION_APP_NAME] function app successfully set"
else
	echo "Failed to set app settings for the [$FUNCTION_APP_NAME] function app"
	exit 1
fi

# Get the resource id of the storage account
echo "Retrieving the resource id of the [$STORAGE_ACCOUNT_NAME] storage account..."
STORAGE_ACCOUNT_RESOURCE_ID=$(az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $STORAGE_ACCOUNT_RESOURCE_ID ]]; then
	echo "Resource id [$STORAGE_ACCOUNT_RESOURCE_ID] of the [$STORAGE_ACCOUNT_NAME] storage account successfully retrieved"
else
	echo "Failed to retrieve the resource id of the [$STORAGE_ACCOUNT_NAME] storage account"
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

# Create the zip package of the function app
cd "$CURRENT_DIR/../function" || exit
if [ -f "$FUNCTION_ZIPFILE" ]; then
	rm "$FUNCTION_ZIPFILE"
fi
echo "Creating zip package of the function app..."
zip -r "$FUNCTION_ZIPFILE" function_app.py host.json requirements.txt

# Deploy the function app
echo "Deploying function app [$FUNCTION_APP_NAME] with zip file [$FUNCTION_ZIPFILE]..."
# On Azure the first deployment to a new function app can time out (504) while its deployment site starts, so a failed
# attempt is retried
DEPLOYED=0
for ((ATTEMPT = 1; ATTEMPT <= DEPLOY_RETRY_COUNT; ATTEMPT++)); do
	az functionapp deploy \
		--resource-group $RESOURCE_GROUP_NAME \
		--name $FUNCTION_APP_NAME \
		--src-path "$FUNCTION_ZIPFILE" \
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
rm -f "$FUNCTION_ZIPFILE"

# The backend address of the API: the Function App's hostname plus the Functions route prefix
FUNCTION_APP_HOSTNAME=$(az functionapp show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query defaultHostName --output tsv)
BACKEND_URL="$BACKEND_SCHEME://$FUNCTION_APP_HOSTNAME/api"
echo "Backend URL = $BACKEND_URL"

# Check if the API already exists
echo "Checking if [$API_ID] API actually exists in the [$APIM_NAME] API Management service..."
az apim api show --api-id $API_ID --service-name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$API_ID] API actually exists in the [$APIM_NAME] API Management service"
	echo "Importing [$API_ID] API from [openapi.json] into the [$APIM_NAME] API Management service..."

	# The operations come from the OpenAPI document; the backend address is given here because
	# it is only known once the Function App exists.
	az apim api import \
		--api-id $API_ID \
		--display-name "$API_DISPLAY_NAME" \
		--path $API_PATH \
		--service-name $APIM_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--specification-format OpenApiJson \
		--specification-path "$APIM_DIR/openapi.json" \
		--service-url "$BACKEND_URL" \
		--subscription-required true 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$API_ID] API successfully imported into the [$APIM_NAME] API Management service"
	else
		echo "Failed to import [$API_ID] API into the [$APIM_NAME] API Management service"
		exit 1
	fi
else
	echo "[$API_ID] API already exists in the [$APIM_NAME] API Management service"
fi

# Apply the API policy. Policies are validated when they are saved, so a mistake in the document
# is reported here rather than at the first request. The body is built with jq so the XML needs
# no escaping by hand. Updating an existing API Management entity needs an If-Match header, and
# * accepts whatever ETag the entity currently has.
echo "Applying the API policy to the [$API_ID] API..."
POLICY_URL="$APIM_ID/apis/$API_ID/policies/policy?api-version=$APIM_API_VERSION"
# rawxml, matching bicep/main.bicep: the shared document is uploaded verbatim, so a policy
# expression containing &&, < or & needs no XML escaping and cannot break this variant alone.
POLICY_BODY=$(jq -n --rawfile xml "$APIM_DIR/inventory-api-policy.xml" '{properties: {format: "rawxml", value: $xml}}')
az rest --method get --url "$POLICY_URL" &>/dev/null

if [[ $? == 0 ]]; then
	az rest --method put --url "$POLICY_URL" --headers "If-Match=*" --body "$POLICY_BODY" --output none
else
	az rest --method put --url "$POLICY_URL" --body "$POLICY_BODY" --output none
fi

if [[ $? == 0 ]]; then
	echo "API policy successfully applied to the [$API_ID] API"
else
	echo "Failed to apply the API policy to the [$API_ID] API"
	exit 1
fi

# Check if the product already exists
echo "Checking if [$PRODUCT_ID] product actually exists in the [$APIM_NAME] API Management service..."
az apim product show --product-id $PRODUCT_ID --service-name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$PRODUCT_ID] product actually exists in the [$APIM_NAME] API Management service"
	echo "Creating [$PRODUCT_ID] product in the [$APIM_NAME] API Management service..."

	az apim product create \
		--product-id $PRODUCT_ID \
		--product-name "$PRODUCT_NAME" \
		--description "Partners reading stock levels through the Inventory API" \
		--service-name $APIM_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--subscription-required true \
		--approval-required false \
		--state published 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$PRODUCT_ID] product successfully created in the [$APIM_NAME] API Management service"
	else
		echo "Failed to create [$PRODUCT_ID] product in the [$APIM_NAME] API Management service"
		exit 1
	fi
else
	echo "[$PRODUCT_ID] product already exists in the [$APIM_NAME] API Management service"
fi

# Check if the product already contains the API
echo "Checking if the [$PRODUCT_ID] product already contains the [$API_ID] API..."
PRODUCT_API_COUNT=$(az apim product api list \
	--product-id "$PRODUCT_ID" \
	--service-name "$APIM_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "length([?name=='$API_ID'])" \
	--output tsv \
	--only-show-errors 2>/dev/null | tr -d '\r')

if [[ $PRODUCT_API_COUNT == 1 ]]; then
	echo "The [$PRODUCT_ID] product already contains the [$API_ID] API"
else
	# Add the API to the product
	echo "Adding the [$API_ID] API to the [$PRODUCT_ID] product..."
	az apim product api add \
		--product-id $PRODUCT_ID \
		--api-id $API_ID \
		--service-name $APIM_NAME \
		--resource-group $RESOURCE_GROUP_NAME 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$API_ID] API successfully added to the [$PRODUCT_ID] product"
	else
		echo "Failed to add the [$API_ID] API to the [$PRODUCT_ID] product"
		exit 1
	fi
fi

# Check if the subscription already exists. The az CLI has no subscription commands, so this goes
# through az rest. The scope is the product: the key opens every API the product contains, and
# nothing else.
echo "Checking if [$APIM_SUBSCRIPTION_ID] subscription actually exists in the [$APIM_NAME] API Management service..."
SUBSCRIPTION_URL="$APIM_ID/subscriptions/$APIM_SUBSCRIPTION_ID?api-version=$APIM_API_VERSION"
az rest --method get --url "$SUBSCRIPTION_URL" &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$APIM_SUBSCRIPTION_ID] subscription actually exists in the [$APIM_NAME] API Management service"
	echo "Creating [$APIM_SUBSCRIPTION_ID] subscription in the [$APIM_NAME] API Management service..."
	PRODUCT_RESOURCE_ID=$(az apim product show --product-id $PRODUCT_ID --service-name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)
	SUBSCRIPTION_BODY=$(jq -n --arg scope "$PRODUCT_RESOURCE_ID" '{properties: {displayName: "Partner subscription", scope: $scope, state: "active"}}')

	az rest --method put --url "$SUBSCRIPTION_URL" --body "$SUBSCRIPTION_BODY" --output none

	if [[ $? == 0 ]]; then
		echo "[$APIM_SUBSCRIPTION_ID] subscription successfully created in the [$APIM_NAME] API Management service"
	else
		echo "Failed to create [$APIM_SUBSCRIPTION_ID] subscription in the [$APIM_NAME] API Management service"
		exit 1
	fi
else
	echo "[$APIM_SUBSCRIPTION_ID] subscription already exists in the [$APIM_NAME] API Management service"
fi

# Check whether the diagnostic settings of the API Management service already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings of the [$APIM_NAME] API Management service already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$APIM_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings of the [$APIM_NAME] API Management service actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings of the [$APIM_NAME] API Management service..."

	# The Consumption tier doesn't support the collection of resource logs: its diagnostic settings send the metrics of
	# the service only. On the other tiers they also send the record of every request through the gateway (GatewayLogs)
	# to the resource-specific ApiManagementGatewayLogs table.
	if [[ $APIM_SKU == "Consumption" ]]; then
		az monitor diagnostic-settings create \
			--name "$DIAGNOSTIC_SETTINGS_NAME" \
			--resource "$APIM_ID" \
			--workspace "$LOG_ANALYTICS_NAME" \
			--metrics '[
				{"category": "AllMetrics", "enabled": true}
			]' \
			--only-show-errors 1>/dev/null
	else
		az monitor diagnostic-settings create \
			--name "$DIAGNOSTIC_SETTINGS_NAME" \
			--resource "$APIM_ID" \
			--workspace "$LOG_ANALYTICS_NAME" \
			--export-to-resource-specific true \
			--logs '[
				{"category": "GatewayLogs", "enabled": true}
			]' \
			--metrics '[
				{"category": "AllMetrics", "enabled": true}
			]' \
			--only-show-errors 1>/dev/null
	fi

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings of the [$APIM_NAME] API Management service successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings of the [$APIM_NAME] API Management service"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings of the [$APIM_NAME] API Management service already exist"
fi

# Where the gateway answers. The emulator also reports Azure's *.azure-api.net address in
# gatewayUrl, but that name only resolves once LocalStack's DNS is in front of the machine, so
# the local alias is printed instead.
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	GATEWAY_URL="http://${APIM_NAME}.apim.azure.localhost.localstack.cloud:4566"
else
	GATEWAY_URL=$(az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME --query gatewayUrl --output tsv)
fi

echo "Deployment completed. The Inventory API is available at: $GATEWAY_URL/$API_PATH"
echo "Read the subscription key with:"
echo "  az rest --method post --url \"$APIM_ID/subscriptions/$APIM_SUBSCRIPTION_ID/listSecrets?api-version=$APIM_API_VERSION\" --query primaryKey --output tsv"
echo "Then call the API with:"
echo "  curl -H \"Ocp-Apim-Subscription-Key: <key>\" \"$GATEWAY_URL/$API_PATH/items\""
