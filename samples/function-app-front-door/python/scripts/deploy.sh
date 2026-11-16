#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
APP_SERVICE_PLAN_NAME="${PREFIX}-catalog-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU='B1'
RUNTIME='python'
RUNTIME_VERSION='3.11'
FUNCTIONS_VERSION='4'
# The two Function Apps are identical apart from their ORIGIN_NAME setting, which is what makes
# origin selection and route matching observable in the response body.
PRIMARY_FUNCTION_APP_NAME="${PREFIX}-catalog-primary-${SUFFIX}"
SECONDARY_FUNCTION_APP_NAME="${PREFIX}-catalog-secondary-${SUFFIX}"
# Storage account names are limited to 24 characters, lower case and digits only.
PRIMARY_STORAGE_ACCOUNT_NAME="${PREFIX}catalogpri${SUFFIX}"
SECONDARY_STORAGE_ACCOUNT_NAME="${PREFIX}catalogsec${SUFFIX}"
PROFILE_NAME="${PREFIX}-catalog-afd-${SUFFIX}"
PROFILE_SKU='Standard_AzureFrontDoor'
ENDPOINT_NAME="${PREFIX}-catalog-${SUFFIX}"
PRIMARY_ORIGIN_GROUP='catalog-origin-group'
STATUS_ORIGIN_GROUP='status-origin-group'
PRIMARY_ORIGIN='primary'
STANDBY_ORIGIN='standby'
SECONDARY_ORIGIN='secondary'
CATCH_ALL_ROUTE='catalog-route'
STATUS_ROUTE='status-route'
RULE_SET_NAME='catalogrules'
# The Functions host serves every HTTP trigger under /api, and the route's origin path puts it
# back on the way to the origin, so clients never see it.
ORIGIN_PATH='/api'
PROBE_PATH='/api/health'
FUNCTION_ZIPFILE='catalog_function.zip'
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
# The two Function Apps send their telemetry to the same Application Insights resource, where cloud_RoleName tells them apart
APPLICATION_INSIGHTS_NAME="${PREFIX}-insights-${SUFFIX}"
DIAGNOSTIC_SETTINGS_NAME='default'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Get the current subscription
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

# The emulator's Function Apps answer on plain HTTP under their own hostnames, while real Azure
# serves *.azurewebsites.net over HTTPS only, so the route reaches the origins over a different
# protocol in each environment. Everything else below is the same on both.
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	FORWARDING_PROTOCOL='HttpOnly'
	HTTPS_REDIRECT='Disabled'
else
	FORWARDING_PROTOCOL='HttpsOnly'
	HTTPS_REDIRECT='Enabled'
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

# Check if the app service plan already exists. Both Function Apps share it, as they would on Azure.
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

	# Create a workspace-based Application Insights component that stores the telemetry of the two Function Apps in the
	# Log Analytics workspace
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

# Create the zip package once; both Function Apps run the same code
cd "$CURRENT_DIR/../function" || exit
if [ -f "$FUNCTION_ZIPFILE" ]; then
	rm "$FUNCTION_ZIPFILE"
fi
echo "Creating zip package of the function app..."
zip -r "$FUNCTION_ZIPFILE" function_app.py host.json requirements.txt

# Create a storage account and a Function App, set the origin name it reports, and deploy the code
create_function_app() {
	local FUNCTION_APP_NAME=$1
	local STORAGE_ACCOUNT_NAME=$2
	local ORIGIN_NAME=$3

	echo "Checking if [$STORAGE_ACCOUNT_NAME] storage account actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
	az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group $RESOURCE_GROUP_NAME &>/dev/null

	if [[ $? != 0 ]]; then
		echo "Creating [$STORAGE_ACCOUNT_NAME] storage account in the [$RESOURCE_GROUP_NAME] resource group..."

		az storage account create \
			--name "$STORAGE_ACCOUNT_NAME" \
			--resource-group $RESOURCE_GROUP_NAME \
			--location "$LOCATION" \
			--sku Standard_LRS 1>/dev/null

		if [[ $? != 0 ]]; then
			echo "Failed to create [$STORAGE_ACCOUNT_NAME] storage account in the [$RESOURCE_GROUP_NAME] resource group"
			exit 1
		fi
		echo "[$STORAGE_ACCOUNT_NAME] storage account successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "[$STORAGE_ACCOUNT_NAME] storage account already exists in the [$RESOURCE_GROUP_NAME] resource group"
	fi

	echo "Checking if [$FUNCTION_APP_NAME] function app actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
	az functionapp show --name "$FUNCTION_APP_NAME" --resource-group $RESOURCE_GROUP_NAME &>/dev/null

	if [[ $? != 0 ]]; then
		echo "Creating [$FUNCTION_APP_NAME] function app in the [$RESOURCE_GROUP_NAME] resource group..."

		az functionapp create \
			--name "$FUNCTION_APP_NAME" \
			--resource-group $RESOURCE_GROUP_NAME \
			--plan $APP_SERVICE_PLAN_NAME \
			--storage-account "$STORAGE_ACCOUNT_NAME" \
			--runtime $RUNTIME \
			--runtime-version $RUNTIME_VERSION \
			--functions-version $FUNCTIONS_VERSION \
			--app-insights "$APPLICATION_INSIGHTS_NAME" \
			--os-type Linux 1>/dev/null

		if [[ $? != 0 ]]; then
			echo "Failed to create [$FUNCTION_APP_NAME] function app in the [$RESOURCE_GROUP_NAME] resource group"
			exit 1
		fi
		echo "[$FUNCTION_APP_NAME] function app successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "[$FUNCTION_APP_NAME] function app already exists in the [$RESOURCE_GROUP_NAME] resource group"
	fi

	# The Functions host keeps its locks and keys in the storage account. az functionapp create builds AzureWebJobsStorage
	# from the storage endpoint suffix of the current cloud, which carries a port on the emulator that the host can't
	# parse, so the setting is written again with the core.windows.net suffix, as on Azure
	echo "Getting the key of the [$STORAGE_ACCOUNT_NAME] storage account..."
	local STORAGE_ACCOUNT_KEY
	STORAGE_ACCOUNT_KEY=$(az storage account keys list \
		--account-name "$STORAGE_ACCOUNT_NAME" \
		--resource-group $RESOURCE_GROUP_NAME \
		--query "[0].value" \
		--output tsv \
		--only-show-errors)

	if [[ -z $STORAGE_ACCOUNT_KEY ]]; then
		echo "Failed to get the key of the [$STORAGE_ACCOUNT_NAME] storage account"
		exit 1
	fi

	echo "Setting app settings for the [$FUNCTION_APP_NAME] function app..."
	az functionapp config appsettings set \
		--name "$FUNCTION_APP_NAME" \
		--resource-group $RESOURCE_GROUP_NAME \
		--settings \
		AzureWebJobsStorage="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT_NAME;AccountKey=$STORAGE_ACCOUNT_KEY;EndpointSuffix=core.windows.net" \
		FUNCTIONS_WORKER_RUNTIME="$RUNTIME" \
		SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
		ENABLE_ORYX_BUILD='true' \
		ORIGIN_NAME="$ORIGIN_NAME" \
		APPLICATIONINSIGHTS_CONNECTION_STRING="$APPLICATION_INSIGHTS_CONNECTION_STRING" \
		PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY='true' \
		PYTHON_APPLICATIONINSIGHTS_LOGGER_NAME='function_app' 1>/dev/null

	if [[ $? != 0 ]]; then
		echo "Failed to set app settings for the [$FUNCTION_APP_NAME] function app"
		exit 1
	fi

	# Get the resource ids of the function app and of its storage account
	local FUNCTION_APP_ID
	local STORAGE_ACCOUNT_RESOURCE_ID
	FUNCTION_APP_ID=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)
	STORAGE_ACCOUNT_RESOURCE_ID=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)

	if [[ -z $FUNCTION_APP_ID || -z $STORAGE_ACCOUNT_RESOURCE_ID ]]; then
		echo "Failed to retrieve the resource ids of the [$FUNCTION_APP_NAME] function app and of its storage account"
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

	echo "Deploying function app [$FUNCTION_APP_NAME] with zip file [$FUNCTION_ZIPFILE]..."
	az functionapp deploy \
		--resource-group $RESOURCE_GROUP_NAME \
		--name "$FUNCTION_APP_NAME" \
		--src-path "$FUNCTION_ZIPFILE" \
		--type zip \
		--async true 1>/dev/null

	if [[ $? != 0 ]]; then
		echo "Failed to deploy function app [$FUNCTION_APP_NAME]"
		exit 1
	fi
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully"
}

create_function_app "$PRIMARY_FUNCTION_APP_NAME" "$PRIMARY_STORAGE_ACCOUNT_NAME" primary
create_function_app "$SECONDARY_FUNCTION_APP_NAME" "$SECONDARY_STORAGE_ACCOUNT_NAME" secondary
rm -f "$FUNCTION_ZIPFILE"

# Get the resource id of the App Service plan
APP_SERVICE_PLAN_ID=$(az appservice plan show --name $APP_SERVICE_PLAN_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)

if [[ -z $APP_SERVICE_PLAN_ID ]]; then
	echo "Failed to retrieve the resource id of the [$APP_SERVICE_PLAN_NAME] App Service plan"
	exit 1
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


# An origin's host name carries no port, so split the one the emulator reports. On Azure the
# default host name is a bare name and the ports below are the standard 80 and 443.
read_origin_address() {
	local FUNCTION_APP_NAME=$1
	local DEFAULT_HOST_NAME

	DEFAULT_HOST_NAME=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group $RESOURCE_GROUP_NAME --query defaultHostName --output tsv)

	if [[ -z "$DEFAULT_HOST_NAME" ]]; then
		echo "Failed to read the default host name of the [$FUNCTION_APP_NAME] function app" >&2
		exit 1
	fi

	ORIGIN_HOST_NAME="${DEFAULT_HOST_NAME%%:*}"
	if [[ "$DEFAULT_HOST_NAME" == *:* ]]; then
		ORIGIN_HTTP_PORT="${DEFAULT_HOST_NAME##*:}"
		ORIGIN_HTTPS_PORT="${DEFAULT_HOST_NAME##*:}"
	else
		ORIGIN_HTTP_PORT=80
		ORIGIN_HTTPS_PORT=443
	fi
	# The origin host header is what the Function App is addressed by, port included: that is the
	# name it is routed by, and the name it reports as WEBSITE_HOSTNAME.
	ORIGIN_HOST_HEADER="$DEFAULT_HOST_NAME"
}

read_origin_address "$PRIMARY_FUNCTION_APP_NAME"
PRIMARY_HOST_NAME=$ORIGIN_HOST_NAME
PRIMARY_HOST_HEADER=$ORIGIN_HOST_HEADER
PRIMARY_HTTP_PORT=$ORIGIN_HTTP_PORT
PRIMARY_HTTPS_PORT=$ORIGIN_HTTPS_PORT

read_origin_address "$SECONDARY_FUNCTION_APP_NAME"
SECONDARY_HOST_NAME=$ORIGIN_HOST_NAME
SECONDARY_HOST_HEADER=$ORIGIN_HOST_HEADER
SECONDARY_HTTP_PORT=$ORIGIN_HTTP_PORT
SECONDARY_HTTPS_PORT=$ORIGIN_HTTPS_PORT

echo "Primary origin:   $PRIMARY_HOST_HEADER"
echo "Secondary origin: $SECONDARY_HOST_HEADER"

# Check if the Front Door profile already exists
echo "Checking if [$PROFILE_NAME] Front Door profile actually exists in the [$RESOURCE_GROUP_NAME] resource group..."
az afd profile show --profile-name $PROFILE_NAME --resource-group $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "Creating [$PROFILE_NAME] Front Door profile in the [$RESOURCE_GROUP_NAME] resource group..."

	az afd profile create \
		--profile-name $PROFILE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--sku $PROFILE_SKU 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$PROFILE_NAME] Front Door profile successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$PROFILE_NAME] Front Door profile in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
else
	echo "[$PROFILE_NAME] Front Door profile already exists in the [$RESOURCE_GROUP_NAME] resource group"
fi

# Get the resource id of the Front Door profile
PROFILE_ID=$(az afd profile show --profile-name $PROFILE_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)

if [[ -z $PROFILE_ID ]]; then
	echo "Failed to retrieve the resource id of the [$PROFILE_NAME] Front Door profile"
	exit 1
fi

# Check whether the diagnostic settings for the Front Door profile already exist
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PROFILE_NAME] Front Door profile already exist..."
az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$PROFILE_ID" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PROFILE_NAME] Front Door profile actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PROFILE_NAME] Front Door profile..."

	# Create the diagnostic settings that send the requests the endpoint served (FrontDoorAccessLog), the health probes
	# of the origins, the records of a web application firewall and the platform metrics of the profile to the Log
	# Analytics workspace. Front Door writes its logs to the AzureDiagnostics table only.
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$PROFILE_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--logs '[
			{"category": "FrontDoorAccessLog", "enabled": true},
			{"category": "FrontDoorHealthProbeLog", "enabled": true},
			{"category": "FrontDoorWebApplicationFirewallLog", "enabled": true}
		]' \
		--metrics '[
			{"category": "AllMetrics", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PROFILE_NAME] Front Door profile successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PROFILE_NAME] Front Door profile"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$PROFILE_NAME] Front Door profile already exist"
fi

# The endpoint is the address clients call; its host name is assigned by Azure
echo "Creating the [$ENDPOINT_NAME] endpoint..."
az afd endpoint create \
	--endpoint-name $ENDPOINT_NAME \
	--profile-name $PROFILE_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--enabled-state Enabled 1>/dev/null

if [[ $? != 0 ]]; then
	echo "Failed to create the [$ENDPOINT_NAME] endpoint"
	exit 1
fi

# Origin groups carry the health probe and the load-balancing settings. The probe is a HEAD
# request to a path the Function App answers; an origin that fails it is taken out of rotation.
create_origin_group() {
	local ORIGIN_GROUP_NAME=$1

	echo "Creating the [$ORIGIN_GROUP_NAME] origin group..."
	az afd origin-group create \
		--origin-group-name "$ORIGIN_GROUP_NAME" \
		--profile-name $PROFILE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--probe-request-type HEAD \
		--probe-protocol Http \
		--probe-path $PROBE_PATH \
		--probe-interval-in-seconds 30 \
		--sample-size 4 \
		--successful-samples-required 3 \
		--additional-latency-in-milliseconds 50 1>/dev/null

	if [[ $? != 0 ]]; then
		echo "Failed to create the [$ORIGIN_GROUP_NAME] origin group"
		exit 1
	fi
}

create_origin_group $PRIMARY_ORIGIN_GROUP
create_origin_group $STATUS_ORIGIN_GROUP

# Priority is a strict tier, not a preference: while a priority-1 origin is healthy, the
# priority-2 origin receives nothing at all.
create_origin() {
	local ORIGIN_GROUP_NAME=$1
	local ORIGIN_NAME=$2
	local HOST_NAME=$3
	local HOST_HEADER=$4
	local HTTP_PORT=$5
	local HTTPS_PORT=$6
	local PRIORITY=$7

	echo "Creating the [$ORIGIN_NAME] origin in the [$ORIGIN_GROUP_NAME] origin group..."
	az afd origin create \
		--origin-name "$ORIGIN_NAME" \
		--origin-group-name "$ORIGIN_GROUP_NAME" \
		--profile-name $PROFILE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--host-name "$HOST_NAME" \
		--origin-host-header "$HOST_HEADER" \
		--http-port "$HTTP_PORT" \
		--https-port "$HTTPS_PORT" \
		--priority "$PRIORITY" \
		--weight 1000 \
		--enabled-state Enabled 1>/dev/null

	if [[ $? != 0 ]]; then
		echo "Failed to create the [$ORIGIN_NAME] origin"
		exit 1
	fi
}

create_origin $PRIMARY_ORIGIN_GROUP $PRIMARY_ORIGIN "$PRIMARY_HOST_NAME" "$PRIMARY_HOST_HEADER" "$PRIMARY_HTTP_PORT" "$PRIMARY_HTTPS_PORT" 1
create_origin $PRIMARY_ORIGIN_GROUP $STANDBY_ORIGIN "$SECONDARY_HOST_NAME" "$SECONDARY_HOST_HEADER" "$SECONDARY_HTTP_PORT" "$SECONDARY_HTTPS_PORT" 2
create_origin $STATUS_ORIGIN_GROUP $SECONDARY_ORIGIN "$SECONDARY_HOST_NAME" "$SECONDARY_HOST_HEADER" "$SECONDARY_HTTP_PORT" "$SECONDARY_HTTPS_PORT" 1

# The rule set: three rules, each one action, applied to the catch-all route.
echo "Creating the [$RULE_SET_NAME] rule set..."
az afd rule-set create \
	--rule-set-name $RULE_SET_NAME \
	--profile-name $PROFILE_NAME \
	--resource-group $RESOURCE_GROUP_NAME 1>/dev/null

if [[ $? != 0 ]]; then
	echo "Failed to create the [$RULE_SET_NAME] rule set"
	exit 1
fi

# `az afd rule create` comes in two spellings. Up to Azure CLI 2.83 the command is part of the CLI
# itself and takes one flattened condition and action; from 2.85 it lives in the `cdn` extension,
# which takes --conditions and --actions in its own shorthand syntax instead. The sample supports
# both, because which one is installed is not the sample's to decide.
if az afd rule create --help 2>/dev/null | grep -q -- '--actions'; then
	AFD_RULE_SYNTAX='extension'
else
	AFD_RULE_SYNTAX='cli'
fi
echo "Creating the rules ($AFD_RULE_SYNTAX syntax)..."

# Rule 1: stamp every response that came through Front Door. The condition matches the request
# method, so it applies to all of the sample's traffic.
if [[ "$AFD_RULE_SYNTAX" == 'extension' ]]; then
	az afd rule create \
		--rule-name stampHeader \
		--rule-set-name $RULE_SET_NAME \
		--profile-name $PROFILE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--order 1 \
		--match-processing-behavior Continue \
		--conditions "[{request-method:{parameters:{operator:Equal,match-values:[GET],negate-condition:false}}}]" \
		--actions "[{modify-response-header:{parameters:{header-action:Overwrite,header-name:X-Served-By,value:front-door}}}]" 1>/dev/null
else
	az afd rule create \
		--rule-name stampHeader \
		--rule-set-name $RULE_SET_NAME \
		--profile-name $PROFILE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--order 1 \
		--match-processing-behavior Continue \
		--match-variable RequestMethod --operator Equal --match-values GET \
		--action-name ModifyResponseHeader --header-action Overwrite --header-name X-Served-By --header-value front-door 1>/dev/null
fi

if [[ $? != 0 ]]; then
	echo "Failed to create the [stampHeader] rule"
	exit 1
fi

# Rule 2: publish the catalog under a friendlier path. Note the match value: the UrlPath condition
# sees the path *without* its leading slash, while UrlRewrite's source pattern keeps it.
if [[ "$AFD_RULE_SYNTAX" == 'extension' ]]; then
	az afd rule create \
		--rule-name rewriteShop \
		--rule-set-name $RULE_SET_NAME \
		--profile-name $PROFILE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--order 2 \
		--match-processing-behavior Continue \
		--conditions "[{url-path:{parameters:{operator:BeginsWith,match-values:[shop],negate-condition:false}}}]" \
		--actions "[{url-rewrite:{parameters:{source-pattern:/shop,destination:/catalog,preserve-unmatched-path:true}}}]" 1>/dev/null
else
	az afd rule create \
		--rule-name rewriteShop \
		--rule-set-name $RULE_SET_NAME \
		--profile-name $PROFILE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--order 2 \
		--match-processing-behavior Continue \
		--match-variable UrlPath --operator BeginsWith --match-values shop \
		--action-name UrlRewrite --source-pattern /shop --destination /catalog --preserve-unmatched-path true 1>/dev/null
fi

if [[ $? != 0 ]]; then
	echo "Failed to create the [rewriteShop] rule"
	exit 1
fi

# Rule 3: retire an old path at the edge. A redirect is terminal, so the origin is never called.
if [[ "$AFD_RULE_SYNTAX" == 'extension' ]]; then
	az afd rule create \
		--rule-name redirectLegacy \
		--rule-set-name $RULE_SET_NAME \
		--profile-name $PROFILE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--order 3 \
		--conditions "[{url-path:{parameters:{operator:BeginsWith,match-values:[legacy],negate-condition:false}}}]" \
		--actions "[{url-redirect:{parameters:{redirect-type:Found,destination-protocol:MatchRequest,custom-path:/status}}}]" 1>/dev/null
else
	az afd rule create \
		--rule-name redirectLegacy \
		--rule-set-name $RULE_SET_NAME \
		--profile-name $PROFILE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--order 3 \
		--match-variable UrlPath --operator BeginsWith --match-values legacy \
		--action-name UrlRedirect --redirect-type Found --redirect-protocol MatchRequest --custom-path /status 1>/dev/null
fi

if [[ $? != 0 ]]; then
	echo "Failed to create the [redirectLegacy] rule"
	exit 1
fi

# The two routes. Caching and rule sets are spelled differently by the two CLI generations too:
# --enable-caching / --rule-sets in the CLI, --cache-configuration / --formatted-rule-sets in the
# extension, which takes resource IDs rather than names.
RULE_SET_ID=$(az afd rule-set show --rule-set-name $RULE_SET_NAME --profile-name $PROFILE_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)

echo "Creating the [$CATCH_ALL_ROUTE] route..."
if [[ "$AFD_RULE_SYNTAX" == 'extension' ]]; then
	az afd route create \
		--route-name $CATCH_ALL_ROUTE \
		--endpoint-name $ENDPOINT_NAME \
		--profile-name $PROFILE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--origin-group $PRIMARY_ORIGIN_GROUP \
		--origin-path $ORIGIN_PATH \
		--patterns-to-match '/*' \
		--supported-protocols Http Https \
		--link-to-default-domain Enabled \
		--https-redirect $HTTPS_REDIRECT \
		--forwarding-protocol $FORWARDING_PROTOCOL \
		--formatted-rule-sets "[{id:'$RULE_SET_ID'}]" \
		--cache-configuration "{query-string-caching-behavior:IgnoreQueryString}" 1>/dev/null
else
	az afd route create \
		--route-name $CATCH_ALL_ROUTE \
		--endpoint-name $ENDPOINT_NAME \
		--profile-name $PROFILE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--origin-group $PRIMARY_ORIGIN_GROUP \
		--origin-path $ORIGIN_PATH \
		--patterns-to-match '/*' \
		--supported-protocols Http Https \
		--link-to-default-domain Enabled \
		--https-redirect $HTTPS_REDIRECT \
		--forwarding-protocol $FORWARDING_PROTOCOL \
		--rule-sets $RULE_SET_NAME \
		--enable-caching true \
		--query-string-caching-behavior IgnoreQueryString 1>/dev/null
fi

if [[ $? != 0 ]]; then
	echo "Failed to create the [$CATCH_ALL_ROUTE] route"
	exit 1
fi

# A more specific pattern wins over the catch-all, whatever order the routes were created in.
# This one has no rule set and no caching, which is how the two routes tell themselves apart.
echo "Creating the [$STATUS_ROUTE] route..."
az afd route create \
	--route-name $STATUS_ROUTE \
	--endpoint-name $ENDPOINT_NAME \
	--profile-name $PROFILE_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--origin-group $STATUS_ORIGIN_GROUP \
	--origin-path $ORIGIN_PATH \
	--patterns-to-match '/status' \
	--supported-protocols Http Https \
	--link-to-default-domain Enabled \
	--https-redirect $HTTPS_REDIRECT \
	--forwarding-protocol $FORWARDING_PROTOCOL 1>/dev/null

if [[ $? != 0 ]]; then
	echo "Failed to create the [$STATUS_ROUTE] route"
	exit 1
fi

# Where the endpoint answers. The emulator also reports Azure's *.azurefd.net address in hostName,
# but that name only resolves once LocalStack's DNS is in front of the machine, so the local alias
# is printed instead.
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	ENDPOINT_URL="http://${ENDPOINT_NAME}.afd.azure.localhost.localstack.cloud:4566"
else
	ENDPOINT_HOST_NAME=$(az afd endpoint show --endpoint-name $ENDPOINT_NAME --profile-name $PROFILE_NAME --resource-group $RESOURCE_GROUP_NAME --query hostName --output tsv)
	ENDPOINT_URL="https://$ENDPOINT_HOST_NAME"
fi

echo "Deployment completed. The catalog is published at: $ENDPOINT_URL"
echo "Try it with:"
echo "  curl -i $ENDPOINT_URL/catalog/1     # cacheable, served by the primary origin"
echo "  curl -i $ENDPOINT_URL/shop/1        # rewritten to /catalog/1 by the rules engine"
echo "  curl -i $ENDPOINT_URL/legacy        # redirected to /status by the rules engine"
echo "  curl -i $ENDPOINT_URL/status        # the more specific route, served by the secondary origin"
echo "  curl -s $ENDPOINT_URL/whoami | jq   # what the origin received"
