#!/bin/bash

# Usage: query-logs-and-metrics.sh
#
# Reads back what the diagnostic settings of the sample sent to its Log Analytics workspace: the records the Functions
# host writes for each invocation of the capture processor (FunctionAppLogs), the exported platform metrics of the
# function app and of its plan (AzureMetrics), the requests to the blobs of the storage account, among them the Capture
# archives (StorageBlobLogs), the transaction metrics of the storage account and of its services, and the audit records
# of the queries run on the workspace (LAQueryLogs). It ends with the executions of the function app, the transactions
# of the storage account, and the messages and captures of the Event Hubs namespace read from the Azure Monitor metrics
# API. Run it after run-pipeline.sh, which sends the readings that Capture archives.
#
# The records reach the workspace within seconds on the emulator, and the metrics once their one-minute window is
# over. On Azure they take minutes, and the first records of a new diagnostic setting can take up to 90 minutes, so
# every query is retried: raise RETRY_COUNT there.

# Variables (the same defaults and environment overrides as the deploy scripts)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
SUFFIX='telemetry'
RESOURCE_GROUP_NAME="${PREFIX}-ehgrid-rg"
FUNCTION_APP_NAME="${PREFIX}-ehgrid-processor"
STORAGE_ACCOUNT_NAME="${PREFIX}ehgrid${SUFFIX:0:4}"
EVENTHUB_NAMESPACE_NAME="${PREFIX}-ehns-${SUFFIX}"
SYSTEM_TOPIC_NAME="${PREFIX}-ehns-systopic"
LOG_ANALYTICS_NAME="${PREFIX}-ehgrid-log-analytics"
RETRY_COUNT="${RETRY_COUNT:-30}"
SLEEP="${SLEEP:-10}"
EXIT_CODE=0

# Run a KQL query on the Log Analytics workspace and print the records it returns as a table, retrying while the
# records are still on their way to the workspace
# $1: what the query reads
# $2: the KQL query
# $3: the JMESPath projection that names and orders the columns of the table
# $4: the number of records the query must return (1 when not given)
query_workspace() {
	local description=$1
	local query=$2
	local columns=$3
	local minimum_records=${4:-1}
	local records
	local attempt=1

	echo -e "\n$description:\n"
	while [ $attempt -le $RETRY_COUNT ]; do
		records=$(az monitor log-analytics query \
			--workspace "$WORKSPACE_ID" \
			--analytics-query "$query" \
			--query "length(@)" \
			--output tsv \
			--only-show-errors)

		if [[ $? == 0 && $records -ge $minimum_records ]]; then
			az monitor log-analytics query \
				--workspace "$WORKSPACE_ID" \
				--analytics-query "$query" \
				--query "$columns" \
				--output table \
				--only-show-errors

			if [[ $? != 0 ]]; then
				echo "ERROR: the [$LOG_ANALYTICS_NAME] Log Analytics workspace did not answer the query that shows the records"
				EXIT_CODE=1
			fi
			return 0
		else
			if [ $attempt -lt $RETRY_COUNT ]; then
				echo "Attempt $attempt of $RETRY_COUNT: [${records:-0}] of the [$minimum_records] records expected so far. Waiting [$SLEEP] seconds before retry..."
				sleep $SLEEP
			fi
			attempt=$((attempt + 1))
		fi
	done

	echo "ERROR: the [$LOG_ANALYTICS_NAME] Log Analytics workspace returned [${records:-0}] of the [$minimum_records] records expected after $RETRY_COUNT attempts."
	echo "On Azure the first records of a new diagnostic setting can take up to 90 minutes: run the script again later or raise RETRY_COUNT."
	EXIT_CODE=1
}

# Show the diagnostic settings of a resource with the log and metric categories they send to the workspace
# $1: the resource id
# $2: the resource description
show_diagnostic_settings() {
	local resource_id=$1
	local description=$2

	echo -e "\nDiagnostic settings of the $description:\n"
	az monitor diagnostic-settings list \
		--resource "$resource_id" \
		--query "[].{Name:name,Logs:join(', ', logs[?enabled].category),Metrics:join(', ', metrics[?enabled].category)}" \
		--output table \
		--only-show-errors

	if [[ $? != 0 ]]; then
		echo "ERROR: failed to read the diagnostic settings of the $description"
		EXIT_CODE=1
	fi
}

# Show the totals of the last hour of the platform metrics of a resource, read from the Azure Monitor metrics API
# $1: the resource id
# $2: the resource description
# $3...: the metric names
show_metrics() {
	local resource_id=$1
	local description=$2
	shift 2

	echo -e "\nPlatform metrics of the $description in the last hour:\n"
	az monitor metrics list \
		--resource "$resource_id" \
		--metrics "$@" \
		--interval PT1M \
		--aggregation Total \
		--offset 1h \
		--query "value[].{Metric:name.value,Unit:unit,Total:sum(timeseries[].data[].total)}" \
		--output table \
		--only-show-errors

	if [[ $? != 0 ]]; then
		echo "ERROR: failed to read the platform metrics of the $description"
		EXIT_CODE=1
	fi
}

# Check whether the log-analytics extension of the Azure CLI, which provides the az monitor log-analytics query
# command, is installed
echo "Checking if the [log-analytics] extension of the Azure CLI is installed..."
az extension show --name log-analytics --only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [log-analytics] extension of the Azure CLI is actually installed"
	echo "Installing the [log-analytics] extension of the Azure CLI..."

	# Install the log-analytics extension
	az extension add \
		--name log-analytics \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[log-analytics] extension of the Azure CLI successfully installed"
	else
		echo "Failed to install the [log-analytics] extension of the Azure CLI"
		exit 1
	fi
else
	echo "[log-analytics] extension of the Azure CLI already installed"
fi

# Get the workspace id (customer id) of the Log Analytics workspace, which identifies it to the query API
echo "Retrieving the workspace id of the [$LOG_ANALYTICS_NAME] Log Analytics workspace..."
WORKSPACE_ID=$(az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query customerId \
	--output tsv \
	--only-show-errors)

if [[ -n $WORKSPACE_ID ]]; then
	echo "Workspace id [$WORKSPACE_ID] of the [$LOG_ANALYTICS_NAME] Log Analytics workspace successfully retrieved"
else
	echo "Failed to retrieve the workspace id of the [$LOG_ANALYTICS_NAME] Log Analytics workspace"
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

# Get the resource id of the App Service plan of the function app
echo "Retrieving the resource id of the App Service plan of the [$FUNCTION_APP_NAME] function app..."
APP_SERVICE_PLAN_ID=$(az functionapp show \
	--name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query appServicePlanId \
	--output tsv \
	--only-show-errors)

if [[ -n $APP_SERVICE_PLAN_ID ]]; then
	echo "Resource id [$APP_SERVICE_PLAN_ID] of the App Service plan successfully retrieved"
else
	echo "Failed to retrieve the resource id of the App Service plan of the [$FUNCTION_APP_NAME] function app"
	exit 1
fi

# Get the resource id of the storage account
echo "Retrieving the resource id of the [$STORAGE_ACCOUNT_NAME] storage account..."
STORAGE_ACCOUNT_ID=$(az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $STORAGE_ACCOUNT_ID ]]; then
	echo "Resource id [$STORAGE_ACCOUNT_ID] of the [$STORAGE_ACCOUNT_NAME] storage account successfully retrieved"
else
	echo "Failed to retrieve the resource id of the [$STORAGE_ACCOUNT_NAME] storage account"
	exit 1
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

# Get the resource ids of the Event Hubs namespace and of the system topic
echo "Retrieving the resource ids of the [$EVENTHUB_NAMESPACE_NAME] Event Hubs namespace and of the [$SYSTEM_TOPIC_NAME] system topic..."
EVENTHUB_NAMESPACE_ID=$(az eventhubs namespace show --name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
SYSTEM_TOPIC_ID=$(az eventgrid system-topic show --name "$SYSTEM_TOPIC_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)

if [[ -n $EVENTHUB_NAMESPACE_ID && -n $SYSTEM_TOPIC_ID ]]; then
	echo "Resource ids of the namespace and of the system topic successfully retrieved"
else
	echo "Failed to retrieve the resource ids of the namespace and of the system topic"
	exit 1
fi

# Show where the diagnostic settings send the logs and metrics of the resources
show_diagnostic_settings "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app"
show_diagnostic_settings "$APP_SERVICE_PLAN_ID" "App Service plan"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID/blobServices/default" "blob service of the [$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID/queueServices/default" "queue service of the [$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID/tableServices/default" "table service of the [$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$LOG_ANALYTICS_ID" "[$LOG_ANALYTICS_NAME] Log Analytics workspace"
show_diagnostic_settings "$EVENTHUB_NAMESPACE_ID" "[$EVENTHUB_NAMESPACE_NAME] Event Hubs namespace"
show_diagnostic_settings "$SYSTEM_TOPIC_ID" "[$SYSTEM_TOPIC_NAME] system topic"

# The records the Functions host writes when an invocation of a function starts and completes, counted per function
# (FunctionAppLogs): their category names the function (Function.<name>)
query_workspace \
	"Records of the invocations per function (FunctionAppLogs)" \
	"FunctionAppLogs | where Category startswith 'Function.' | summarize Records = count() by FunctionName | order by FunctionName asc" \
	"[].{Function:FunctionName,Records:Records}"

# The platform metrics the AllMetrics category of the diagnostic settings exports to the workspace (AzureMetrics), one
# record per metric and minute. The Consumption plan of the function app has no CPU and memory metrics, and on Azure each
# resource's metrics start arriving at their own pace, so the query waits for the first of them and shows those that
# arrived.
query_workspace \
	"Platform metrics exported to the [$LOG_ANALYTICS_NAME] Log Analytics workspace (AzureMetrics)" \
	"AzureMetrics | summarize Total = sum(Total) by ResourceProvider, Resource, MetricName | order by ResourceProvider asc, Resource asc, MetricName asc | take 20" \
	"[].{Provider:ResourceProvider,Resource:Resource,Metric:MetricName,Total:Total}"

# The requests to the blobs of the storage account (StorageBlobLogs, from the diagnostic setting of the blob service):
# Event Hubs Capture writes the archives there, the function reads them, and the Functions host keeps its locks, keys
# and checkpoints there
query_workspace \
	"Latest requests to the blobs of the [$STORAGE_ACCOUNT_NAME] storage account (StorageBlobLogs)" \
	"StorageBlobLogs | where AccountName =~ '$STORAGE_ACCOUNT_NAME' | project TimeGenerated, OperationName, StatusCode, AuthenticationType, ObjectKey | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Operation:OperationName,Status:StatusCode,Authentication:AuthenticationType,Object:ObjectKey}"

# The transaction metrics that the diagnostic settings of the storage account and of its services export to the
# workspace (AzureMetrics), one record per metric and minute for each of them
query_workspace \
	"Transaction metrics of the [$STORAGE_ACCOUNT_NAME] storage account exported to the workspace (AzureMetrics)" \
	"AzureMetrics | where _ResourceId startswith '$STORAGE_ACCOUNT_ID' and MetricName == 'Transactions' | extend Scope = case(_ResourceId endswith '/blobServices/default', 'blob service', _ResourceId endswith '/queueServices/default', 'queue service', _ResourceId endswith '/tableServices/default', 'table service', 'storage account') | summarize Minutes = count(), Total = sum(Total) by Scope, MetricName | order by Scope asc" \
	"[].{Scope:Scope,Metric:MetricName,Minutes:Minutes,Total:Total}" \
	2

# The audit records of the queries run on the workspace, among them the ones above (LAQueryLogs, from the diagnostic
# setting of the workspace itself)
query_workspace \
	"Latest queries run on the [$LOG_ANALYTICS_NAME] Log Analytics workspace (LAQueryLogs)" \
	"LAQueryLogs | project TimeGenerated, ResponseCode, Query = substring(QueryText, 0, 80) | order by TimeGenerated desc | take 5" \
	"[].{Time:TimeGenerated,Response:ResponseCode,Query:Query}"

# The executions of the function app, the transactions of the storage account, and the messages and captures of the
# namespace, read from the Azure Monitor metrics API: they need no diagnostic setting
show_metrics "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app" FunctionExecutionCount
show_metrics "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account" Transactions Ingress Egress
show_metrics "$EVENTHUB_NAMESPACE_ID" "[$EVENTHUB_NAMESPACE_NAME] Event Hubs namespace" IncomingMessages OutgoingMessages CapturedMessages

exit $EXIT_CODE
