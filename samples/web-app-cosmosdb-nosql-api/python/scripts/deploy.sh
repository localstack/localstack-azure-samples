#!/bin/bash


PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
WEB_APP_NAME="${PREFIX}-webapp-nosql-${SUFFIX}"
# The App Service plan and the Cosmos DB account are named after the web app
APP_SERVICE_PLAN_NAME="${WEB_APP_NAME}"
APP_SERVICE_PLAN_SKU="B1"
COSMOSDB_ACCOUNT_NAME="${WEB_APP_NAME}"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-insights-${SUFFIX}"
DIAGNOSTIC_SETTINGS_NAME='default'
ZIPFILE="${WEB_APP_NAME}.zip"

# The database and the container keep their names from run to run, so that a second run finds them instead of
# creating new ones and pointing the web app at an empty container
AZURECOSMOSDB_DATABASENAME="${AZURECOSMOSDB_DATABASENAME:-vacationplanner}"
AZURECOSMOSDB_CONTAINERNAME="${AZURECOSMOSDB_CONTAINERNAME:-activities}"
AURECOSMOSDB_PARTITION_KEY="/username"

# run-samples.sh runs this script as `bash scripts/deploy.sh` from the sample root, so relative
# paths such as ../src must resolve against the script's own location, not the caller's directory.
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$CURRENT_DIR" || exit

# Validates if the resource group exists in the subscription, if not creates it
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists"
	echo "Creating resource group [$RESOURCE_GROUP_NAME]..."

	# Create the resource group
    az group create \
        --name $RESOURCE_GROUP_NAME \
        --location $LOCATION \
        --only-show-errors 1> /dev/null \

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created."
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
		exit 1
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists."
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

# Check if the Cosmos DB account already exists
echo "Checking if [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account exists in the [$RESOURCE_GROUP_NAME] resource group..."
if az cosmosdb show --resource-group "$RESOURCE_GROUP_NAME" --name "$COSMOSDB_ACCOUNT_NAME" --only-show-errors &>/dev/null; then
	echo "[$COSMOSDB_ACCOUNT_NAME] Cosmos DB account already exists in the [$RESOURCE_GROUP_NAME] resource group"
else
	# Create the Cosmos DB account
	echo "Creating [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account in the [$RESOURCE_GROUP_NAME] resource group..."
	if az cosmosdb create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$COSMOSDB_ACCOUNT_NAME" \
		--locations regionName="$LOCATION" \
		--only-show-errors 1>/dev/null; then
		echo "[$COSMOSDB_ACCOUNT_NAME] Cosmos DB account successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
fi

# Get the document endpoint of the Cosmos DB account
AZURECOSMOSDB_ENDPOINT=$(az cosmosdb show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--query "documentEndpoint" \
	--output tsv \
	--only-show-errors)

if [[ -n $AZURECOSMOSDB_ENDPOINT ]]; then
	echo "AZURECOSMOSDB_ENDPOINT set to $AZURECOSMOSDB_ENDPOINT"
else
	echo "Failed to retrieve the document endpoint of the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account"
	exit 1
fi
export AZURECOSMOSDB_ENDPOINT

# Get the resource id of the Cosmos DB account
COSMOSDB_ACCOUNT_ID=$(az cosmosdb show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$COSMOSDB_ACCOUNT_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -z $COSMOSDB_ACCOUNT_ID ]]; then
	echo "Failed to retrieve the resource id of the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account"
	exit 1
fi

# Check whether the diagnostic settings for the Cosmos DB account already exist and send its logs to resource-specific
# tables. They're created before the database and the container, so that their creation is among the control plane
# requests of the account.
echo "Checking if [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account already exist..."
COSMOSDB_ACCOUNT_DESTINATION_TYPE=$(az monitor diagnostic-settings show \
	--name "$DIAGNOSTIC_SETTINGS_NAME" \
	--resource "$COSMOSDB_ACCOUNT_ID" \
	--query logAnalyticsDestinationType \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ $COSMOSDB_ACCOUNT_DESTINATION_TYPE != "Dedicated" ]]; then
	echo "No [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account that send its logs to resource-specific tables actually exist"
	echo "Creating [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account..."

	# Create the diagnostic settings for the Cosmos DB account to send the requests of the app (CDBDataPlaneRequests)
	# and the requests Azure Resource Manager sends to the account (CDBControlPlaneRequests) to the Log Analytics
	# workspace, in resource-specific tables rather than AzureDiagnostics
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$COSMOSDB_ACCOUNT_ID" \
		--workspace "$LOG_ANALYTICS_NAME" \
		--export-to-resource-specific true \
		--logs '[
			{"category": "DataPlaneRequests", "enabled": true},
			{"category": "ControlPlaneRequests", "enabled": true}
		]' \
		--metrics '[
			{"category": "Requests", "enabled": true}
		]' \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account successfully created"
	else
		echo "Failed to create [$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account"
		exit 1
	fi
else
	echo "[$DIAGNOSTIC_SETTINGS_NAME] diagnostic settings for the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account already exist"
fi

if az cosmosdb sql database show --resource-group "$RESOURCE_GROUP_NAME" --account-name "$COSMOSDB_ACCOUNT_NAME" --name "$AZURECOSMOSDB_DATABASENAME" --only-show-errors &>/dev/null; then
	echo "[$AZURECOSMOSDB_DATABASENAME] database in the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account already exists."
else
	# Create the Cosmos DB database
	echo "Creating [$AZURECOSMOSDB_DATABASENAME] database in the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account..."
	az cosmosdb sql database create \
		--resource-group $RESOURCE_GROUP_NAME \
		--name $AZURECOSMOSDB_DATABASENAME \
		--account-name $COSMOSDB_ACCOUNT_NAME \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$AZURECOSMOSDB_DATABASENAME] database successfully created in the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account"
	else
		echo "Failed to create [$AZURECOSMOSDB_DATABASENAME] database in the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account"
		exit 1
	fi
fi

if az cosmosdb sql container show --resource-group "$RESOURCE_GROUP_NAME" --account-name "$COSMOSDB_ACCOUNT_NAME" --database-name "$AZURECOSMOSDB_DATABASENAME" --name "$AZURECOSMOSDB_CONTAINERNAME" --only-show-errors &>/dev/null; then
	echo "[$AZURECOSMOSDB_CONTAINERNAME] container in the [$AZURECOSMOSDB_DATABASENAME] database already exists."
else
	# Create the Cosmos DB container
	echo "Creating [$AZURECOSMOSDB_CONTAINERNAME] container in the [$AZURECOSMOSDB_DATABASENAME] database..."
	az cosmosdb sql container create \
		--resource-group $RESOURCE_GROUP_NAME \
		--account-name $COSMOSDB_ACCOUNT_NAME \
		--database-name $AZURECOSMOSDB_DATABASENAME \
		--name $AZURECOSMOSDB_CONTAINERNAME \
		--partition-key-path $AURECOSMOSDB_PARTITION_KEY \
		--throughput 400 \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$AZURECOSMOSDB_CONTAINERNAME] container successfully created in the [$AZURECOSMOSDB_DATABASENAME] database"
	else
		echo "Failed to create [$AZURECOSMOSDB_CONTAINERNAME] container in the [$AZURECOSMOSDB_DATABASENAME] database"
		exit 1
	fi
fi

# Retrieve the primary key of the Cosmos DB account
echo "Retrieving the primary key of the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account..."
AZURECOSMOSDB_PRIMARY_KEY=$(az cosmosdb keys list \
	--resource-group $RESOURCE_GROUP_NAME \
	--name $COSMOSDB_ACCOUNT_NAME \
	--query "primaryMasterKey" \
	--output tsv)

if [[ -n $AZURECOSMOSDB_PRIMARY_KEY ]]; then
	echo "Successfully retrieved the primary key of the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account"
else
	echo "Failed to retrieve the primary key of the [$COSMOSDB_ACCOUNT_NAME] Cosmos DB account"
	exit 1
fi
export AZURECOSMOSDB_PRIMARY_KEY

if az appservice plan show --name "$APP_SERVICE_PLAN_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	echo "App service plan [$APP_SERVICE_PLAN_NAME] already exists."
else
	# Create the App Service plan
	echo "Creating [$APP_SERVICE_PLAN_NAME] App Service plan in the [$RESOURCE_GROUP_NAME] resource group..."
	az appservice plan create \
		--name $APP_SERVICE_PLAN_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--sku $APP_SERVICE_PLAN_SKU \
		--is-linux \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$APP_SERVICE_PLAN_NAME] App Service plan successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$APP_SERVICE_PLAN_NAME] App Service plan in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
fi

if az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	echo "Web app [$WEB_APP_NAME] already exists."
else
	# Create the web app
	echo "Creating [$WEB_APP_NAME] web app in the [$RESOURCE_GROUP_NAME] resource group..."
	az webapp create \
		--name $WEB_APP_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--plan $APP_SERVICE_PLAN_NAME \
		--runtime PYTHON:3.13 \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$WEB_APP_NAME] web app successfully created in the [$RESOURCE_GROUP_NAME] resource group"
	else
		echo "Failed to create [$WEB_APP_NAME] web app in the [$RESOURCE_GROUP_NAME] resource group"
		exit 1
	fi
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

# Set the application settings of the web app. The package holds the source code, so the deployment builds it:
# without SCM_DO_BUILD_DURING_DEPLOYMENT, az webapp deploy only copies the files and Azure serves its welcome page
echo "Setting the application settings of the [$WEB_APP_NAME] web app..."
az webapp config appsettings set \
	--resource-group $RESOURCE_GROUP_NAME \
	--name $WEB_APP_NAME \
	--settings SCM_DO_BUILD_DURING_DEPLOYMENT='true' \
	ENABLE_ORYX_BUILD='true' \
	AZURECOSMOSDB_ENDPOINT=$AZURECOSMOSDB_ENDPOINT \
	AZURECOSMOSDB_DATABASENAME=$AZURECOSMOSDB_DATABASENAME \
	AZURECOSMOSDB_CONTAINERNAME=$AZURECOSMOSDB_CONTAINERNAME \
	AZURECOSMOSDB_PRIMARY_KEY=$AZURECOSMOSDB_PRIMARY_KEY \
	APPLICATIONINSIGHTS_CONNECTION_STRING="$APPLICATION_INSIGHTS_CONNECTION_STRING" \
	--only-show-errors 1>/dev/null

if [[ $? == 0 ]]; then
	echo "Application settings of the [$WEB_APP_NAME] web app successfully set"
else
	echo "Failed to set the application settings of the [$WEB_APP_NAME] web app"
	exit 1
fi

# Print the names of the application settings of the web app, never their values, which include the account key
echo "Names of the application settings of the [$WEB_APP_NAME] web app:"
az webapp config appsettings list \
	--resource-group $RESOURCE_GROUP_NAME \
	--name $WEB_APP_NAME \
	--query "[].name" \
	--output tsv

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


# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py cosmosdb_client.py gunicorn.conf.py static templates requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
echo "Using az webapp deploy command for LocalStack emulator environment."
# On Azure the deployment service can answer 504 Gateway Timeout while it warms up, or DeploymentInProgress while
# the build of the previous deployment still runs: the upload is tried again. The startup of the site isn't
# tracked: the tracking counted a failed start of the container that ran before the code was deployed, and
# reported a running site as failed after ten minutes; what calls the web app afterwards waits for it instead.
WEBAPP_DEPLOY_RETRY_COUNT="${WEBAPP_DEPLOY_RETRY_COUNT:-10}"
WEBAPP_DEPLOY_RETRY_SLEEP="${WEBAPP_DEPLOY_RETRY_SLEEP:-30}"
WEBAPP_DEPLOYED=0
for ATTEMPT in $(seq 1 "$WEBAPP_DEPLOY_RETRY_COUNT"); do
	if az webapp deploy \
		--resource-group $RESOURCE_GROUP_NAME \
		--name $WEB_APP_NAME \
		--src-path ${ZIPFILE} \
		--type zip \
		--async true \
		--track-status false; then
		WEBAPP_DEPLOYED=1
		break
	fi
	if [ "$ATTEMPT" -lt "$WEBAPP_DEPLOY_RETRY_COUNT" ]; then
		echo "Attempt $ATTEMPT of $WEBAPP_DEPLOY_RETRY_COUNT to deploy web app [$WEB_APP_NAME] failed. Waiting [$WEBAPP_DEPLOY_RETRY_SLEEP] seconds before retry..."
		sleep "$WEBAPP_DEPLOY_RETRY_SLEEP"
	fi
done

if [ $WEBAPP_DEPLOYED -eq 1 ]; then
	echo "[$ZIPFILE] zip package successfully deployed to the [$WEB_APP_NAME] web app"
else
	echo "Failed to deploy [$ZIPFILE] zip package to the [$WEB_APP_NAME] web app"
	exit 1
fi

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi
