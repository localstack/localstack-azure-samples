#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
FUNCTION_APP_NAME="${PREFIX}-functionapp-${SUFFIX}"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="B1"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
RUNTIME="dotnet-isolated"
RUNTIME_VERSION="10"
INPUT_STORAGE_CONTAINER_NAME='input'
OUTPUT_STORAGE_CONTAINER_NAME='output'
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-insights-${SUFFIX}"
DIAGNOSTIC_SETTINGS_NAME="default"
ZIPFILE="function_app.zip"
DEPLOY_RETRY_COUNT=3
DEPLOY_RETRY_SLEEP=30
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
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
		--location $LOCATION \
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
		--location $LOCATION \
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

# Construct the storage connection string for LocalStack
STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT_NAME;AccountKey=$STORAGE_ACCOUNT_KEY;EndpointSuffix=core.windows.net"
echo "Storage connection string constructed."

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

# Check if the input blob container exists
echo "Checking if input blob container [$INPUT_STORAGE_CONTAINER_NAME] exists in the [$STORAGE_ACCOUNT_NAME] storage account..."
az storage container show \
	--name "$INPUT_STORAGE_CONTAINER_NAME" \
	--account-name "$STORAGE_ACCOUNT_NAME" \
	--account-key "$STORAGE_ACCOUNT_KEY" &>/dev/null

if [[ $? != 0 ]]; then

	# Create input blob container
	echo "Creating input blob container [$INPUT_STORAGE_CONTAINER_NAME] in the [$STORAGE_ACCOUNT_NAME] storage account..."
	az storage container create \
		--name "$INPUT_STORAGE_CONTAINER_NAME" \
		--account-name "$STORAGE_ACCOUNT_NAME" \
		--account-key "$STORAGE_ACCOUNT_KEY"

	if [ $? -eq 0 ]; then
		echo "Input blob container [$INPUT_STORAGE_CONTAINER_NAME] created successfully in the [$STORAGE_ACCOUNT_NAME] storage account."
	else
		echo "Failed to create input blob container [$INPUT_STORAGE_CONTAINER_NAME] in the [$STORAGE_ACCOUNT_NAME] storage account."
		exit 1
	fi
fi

# Check if the output blob container exists
echo "Checking if output blob container [$OUTPUT_STORAGE_CONTAINER_NAME] exists in the [$STORAGE_ACCOUNT_NAME] storage account..."
az storage container show \
	--name "$OUTPUT_STORAGE_CONTAINER_NAME" \
	--account-name "$STORAGE_ACCOUNT_NAME" \
	--account-key "$STORAGE_ACCOUNT_KEY" &>/dev/null

if [[ $? != 0 ]]; then
	# Create output blob container
	echo "Creating output blob container [$OUTPUT_STORAGE_CONTAINER_NAME] in the [$STORAGE_ACCOUNT_NAME] storage account..."
	az storage container create \
		--name "$OUTPUT_STORAGE_CONTAINER_NAME" \
		--account-name "$STORAGE_ACCOUNT_NAME" \
		--account-key "$STORAGE_ACCOUNT_KEY"

	if [ $? -eq 0 ]; then
		echo "Output blob container [$OUTPUT_STORAGE_CONTAINER_NAME] created successfully in the [$STORAGE_ACCOUNT_NAME] storage account."
	else
		echo "Failed to create output blob container [$OUTPUT_STORAGE_CONTAINER_NAME] in the [$STORAGE_ACCOUNT_NAME] storage account."
		exit 1
	fi
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

# Check if the App Service plan already exists
echo "Checking if App Service plan [$APP_SERVICE_PLAN_NAME] exists in the resource group [$RESOURCE_GROUP_NAME]..."
az appservice plan show \
	--name "$APP_SERVICE_PLAN_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No App Service plan [$APP_SERVICE_PLAN_NAME] exists in the [$RESOURCE_GROUP_NAME] resource group."
	echo "Creating App Service plan [$APP_SERVICE_PLAN_NAME]..."

	# Create a Linux App Service plan for the function app: .NET 9 is the last .NET version that the Linux Consumption
	# plan supports (https://learn.microsoft.com/azure/azure-functions/supported-languages)
	az appservice plan create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$APP_SERVICE_PLAN_NAME" \
		--location "$LOCATION" \
		--sku "$APP_SERVICE_PLAN_SKU" \
		--is-linux \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "App Service plan [$APP_SERVICE_PLAN_NAME] created successfully."
	else
		echo "Failed to create App Service plan [$APP_SERVICE_PLAN_NAME]."
		exit 1
	fi
else
	echo "App Service plan [$APP_SERVICE_PLAN_NAME] already exists in the [$RESOURCE_GROUP_NAME] resource group."
fi

# Create the function app on the App Service plan, which also turns on Always On, so that the blob trigger keeps
# running. The --app-insights parameter connects the function app to the Application Insights component through its
# APPLICATIONINSIGHTS_CONNECTION_STRING app setting.
echo "Creating function app [$FUNCTION_APP_NAME]..."
az functionapp create \
	--resource-group $RESOURCE_GROUP_NAME \
	--plan "$APP_SERVICE_PLAN_NAME" \
	--assign-identity '[system]' \
	--runtime $RUNTIME \
	--runtime-version $RUNTIME_VERSION \
	--functions-version 4 \
	--name $FUNCTION_APP_NAME \
	--app-insights "$APPLICATION_INSIGHTS_NAME" \
	--storage-account $STORAGE_ACCOUNT_NAME \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Function app [$FUNCTION_APP_NAME] created successfully."
else
	echo "Failed to create function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Retrieve the principalId of the system-assigned managed identity
MANAGED_IDENTITY_PRINCIPAL_ID=$(az functionapp identity show \
	--name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query principalId \
	--output tsv)

if [ -n "$MANAGED_IDENTITY_PRINCIPAL_ID" ]; then
	echo "Principal ID of the system-assigned managed identity of the function app [$FUNCTION_APP_NAME] retrieved successfully"
else
	echo "Failed to retrieve principal ID of the system-assigned managed identity of the function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Assign the Storage Blob Data Contributor role to the managed identity with the storage account as scope
ROLE="Storage Blob Data Contributor"
echo "Checking if the managed identity with principal ID [$MANAGED_IDENTITY_PRINCIPAL_ID] has the [$ROLE] role assignment on storage account [$STORAGE_ACCOUNT_NAME]..."
current=$(az role assignment list \
	--assignee "$MANAGED_IDENTITY_PRINCIPAL_ID" \
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
			--assignee-object-id "$MANAGED_IDENTITY_PRINCIPAL_ID" \
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

# Assign the Storage Queue Data Contributor role to the managed identity with the storage account as scope
ROLE="Storage Queue Data Contributor"
echo "Checking if the managed identity with principal ID [$MANAGED_IDENTITY_PRINCIPAL_ID] has the [$ROLE] role assignment on storage account [$STORAGE_ACCOUNT_NAME]..."
current=$(az role assignment list \
	--assignee "$MANAGED_IDENTITY_PRINCIPAL_ID" \
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
			--assignee-object-id "$MANAGED_IDENTITY_PRINCIPAL_ID" \
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

# Set function app settings
echo "Setting function app settings for [$FUNCTION_APP_NAME]..."

# Get the blob, queue and table endpoints of the storage account, which the identity-based connection of the function
# uses
read -r BLOB_SERVICE_URI QUEUE_SERVICE_URI TABLE_SERVICE_URI < <(az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[primaryEndpoints.blob, primaryEndpoints.queue, primaryEndpoints.table]" \
	--output tsv \
	--only-show-errors | tr '\n' ' ')

if [[ -n $BLOB_SERVICE_URI && -n $QUEUE_SERVICE_URI && -n $TABLE_SERVICE_URI ]]; then
	echo "Blob, queue and table endpoints of the [$STORAGE_ACCOUNT_NAME] storage account successfully retrieved"
else
	echo "Failed to retrieve the blob, queue and table endpoints of the [$STORAGE_ACCOUNT_NAME] storage account"
	exit 1
fi


az functionapp config appsettings set \
	--name $FUNCTION_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--settings \
	SCM_DO_BUILD_DURING_DEPLOYMENT='false' \
	AzureWebJobsStorage="$STORAGE_CONNECTION_STRING" \
	STORAGE_ACCOUNT_CONNECTION_STRING__blobServiceUri="$BLOB_SERVICE_URI" \
	STORAGE_ACCOUNT_CONNECTION_STRING__queueServiceUri="$QUEUE_SERVICE_URI" \
	STORAGE_ACCOUNT_CONNECTION_STRING__tableServiceUri="$TABLE_SERVICE_URI" \
	INPUT_STORAGE_CONTAINER_NAME="$INPUT_STORAGE_CONTAINER_NAME" \
	OUTPUT_STORAGE_CONTAINER_NAME="$OUTPUT_STORAGE_CONTAINER_NAME" \
	FUNCTIONS_WORKER_RUNTIME="$RUNTIME" \
	FUNCTIONS_EXTENSION_VERSION="~4" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Function app settings for [$FUNCTION_APP_NAME] set successfully."
else
	echo "Failed to set function app settings for [$FUNCTION_APP_NAME]."
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

# CD into the function app directory
cd ../src/sample || exit

# Publish the project in Release configuration to a publish directory
echo "Publishing the function app..."
dotnet publish -c Release -o publish || exit 1

# Remove any existing zip package of the function app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the function app
echo "Creating zip package of the function app..."
(cd publish && zip -r "../$ZIPFILE" .) || exit 1

# Deploy the function app
echo "Deploying function app [$FUNCTION_APP_NAME] with zip file [$ZIPFILE]..."
#az functionapp deployment source config-zip \
#	--resource-group "$RESOURCE_GROUP_NAME" \
#	--name "$FUNCTION_APP_NAME" \
#	--src "$ZIPFILE" 1>/dev/null
# On Azure the first deployment to a new function app can time out (504) while its deployment site starts, so a failed
# attempt is retried
DEPLOYED=0
for ((ATTEMPT = 1; ATTEMPT <= DEPLOY_RETRY_COUNT; ATTEMPT++)); do
	az functionapp deploy \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$FUNCTION_APP_NAME" \
		--src-path "$ZIPFILE" \
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
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully."
else
	echo "Failed to deploy function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Remove the zip package of the function app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi
