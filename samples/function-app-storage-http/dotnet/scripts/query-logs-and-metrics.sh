#!/bin/bash

# Usage: query-logs-and-metrics.sh
#
# Reads back what the diagnostic settings of the sample sent to its Log Analytics workspace: the records the Functions
# host writes for each invocation of the functions (FunctionAppLogs), first those of the CreateGame timer function,
# which runs when the host starts and then every minute, the exported platform metrics of the function app and of its
# App Service plan (AzureMetrics), the requests to the blobs, the queues and the tables of the storage account
# (StorageBlobLogs, StorageQueueLogs, StorageTableLogs) and the transaction metrics of the storage account and of its
# services, and the audit records of the queries run on the workspace (LAQueryLogs). It ends with the executions of the
# function app and the transactions of the storage account read from the Azure Monitor metrics API. The timer keeps the
# function app busy by itself, so the script calls nothing.
#
# The records reach the workspace within seconds on the emulator, and the metrics once their one-minute window is
# over. On Azure they take minutes, and the first records of a new diagnostic setting can take up to 90 minutes, so
# every query is retried: raise RETRY_COUNT there.

# Variables (the same defaults and environment overrides as the deploy scripts)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
FUNCTION_APP_NAME="${PREFIX}-functionapp-${SUFFIX}"
TIMER_FUNCTION_NAME="CreateGame"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
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

# Show where the diagnostic settings send the logs and metrics of the resources
show_diagnostic_settings "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app"
show_diagnostic_settings "$APP_SERVICE_PLAN_ID" "App Service plan"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID/blobServices/default" "blob service of the [$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID/queueServices/default" "queue service of the [$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID/tableServices/default" "table service of the [$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$LOG_ANALYTICS_ID" "[$LOG_ANALYTICS_NAME] Log Analytics workspace"

# The records the Functions host writes when an invocation of the timer function starts and completes
# (FunctionAppLogs): their category names the function (Function.<name>)
query_workspace \
	"Latest records of the invocations of the [$TIMER_FUNCTION_NAME] function (FunctionAppLogs)" \
	"FunctionAppLogs | where Category == 'Function.$TIMER_FUNCTION_NAME' | project TimeGenerated, FunctionName, EventName, Level, Message | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Function:FunctionName,Event:EventName,Level:Level,Message:Message}" \
	2

# The records of the invocations of every function of the function app, counted per function (FunctionAppLogs)
query_workspace \
	"Records of the invocations of the functions of the [$FUNCTION_APP_NAME] function app (FunctionAppLogs)" \
	"FunctionAppLogs | where Category startswith 'Function.' | summarize Records = count() by FunctionName | order by FunctionName asc" \
	"[].{Function:FunctionName,Records:Records}"

# The executions of the function app that the AllMetrics category of its diagnostic setting exports to the workspace
# (AzureMetrics), one record per minute, exported once the minute is over. On Azure an execution can be counted in a
# minute after the one in which it ran.
query_workspace \
	"Executions of the [$FUNCTION_APP_NAME] function app exported to the workspace (AzureMetrics)" \
	"AzureMetrics | where _ResourceId =~ '$FUNCTION_APP_ID' and MetricName == 'FunctionExecutionCount' | summarize Minutes = count(), Total = sum(Total) by Resource, MetricName" \
	"[].{Resource:Resource,Metric:MetricName,Minutes:Minutes,Total:Total}"

# The platform metrics of the App Service plan that the AllMetrics category of its diagnostic setting exports to the
# workspace (AzureMetrics): the average use of the CPU and of the memory of its instances in each minute
query_workspace \
	"Platform metrics of the App Service plan exported to the workspace (AzureMetrics)" \
	"AzureMetrics | where _ResourceId =~ '$APP_SERVICE_PLAN_ID' and MetricName in ('CpuPercentage', 'MemoryPercentage') | summarize Minutes = count(), Average = avg(Average) by Resource, MetricName | order by MetricName asc" \
	"[].{Resource:Resource,Metric:MetricName,Minutes:Minutes,Average:Average}"

# The requests to the blobs, the queues and the tables of the storage account, from the diagnostic settings of its
# services: the functions and the Functions host authenticate with the account key (AccountKey)
query_workspace \
	"Latest requests to the blobs of the [$STORAGE_ACCOUNT_NAME] storage account (StorageBlobLogs)" \
	"StorageBlobLogs | where AccountName =~ '$STORAGE_ACCOUNT_NAME' | project TimeGenerated, OperationName, StatusCode, AuthenticationType, ObjectKey | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Operation:OperationName,Status:StatusCode,Authentication:AuthenticationType,Object:ObjectKey}"

query_workspace \
	"Latest requests to the queues of the [$STORAGE_ACCOUNT_NAME] storage account (StorageQueueLogs)" \
	"StorageQueueLogs | where AccountName =~ '$STORAGE_ACCOUNT_NAME' | project TimeGenerated, OperationName, StatusCode, AuthenticationType, ObjectKey | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Operation:OperationName,Status:StatusCode,Authentication:AuthenticationType,Object:ObjectKey}"

query_workspace \
	"Latest requests to the tables of the [$STORAGE_ACCOUNT_NAME] storage account (StorageTableLogs)" \
	"StorageTableLogs | where AccountName =~ '$STORAGE_ACCOUNT_NAME' | project TimeGenerated, OperationName, StatusCode, AuthenticationType, ObjectKey | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Operation:OperationName,Status:StatusCode,Authentication:AuthenticationType,Object:ObjectKey}"

# The transaction metrics that the diagnostic settings of the storage account and of its services export to the
# workspace (AzureMetrics), one record per metric and minute for each of them
query_workspace \
	"Transaction metrics of the [$STORAGE_ACCOUNT_NAME] storage account exported to the workspace (AzureMetrics)" \
	"AzureMetrics | where _ResourceId startswith '$STORAGE_ACCOUNT_ID' and MetricName == 'Transactions' | extend Scope = case(_ResourceId endswith '/blobServices/default', 'blob service', _ResourceId endswith '/queueServices/default', 'queue service', _ResourceId endswith '/tableServices/default', 'table service', 'storage account') | summarize Minutes = count(), Total = sum(Total) by Scope, MetricName | order by Scope asc" \
	"[].{Scope:Scope,Metric:MetricName,Minutes:Minutes,Total:Total}" \
	4

# The audit records of the queries run on the workspace, among them the ones above (LAQueryLogs, from the diagnostic
# setting of the workspace itself)
query_workspace \
	"Latest queries run on the [$LOG_ANALYTICS_NAME] Log Analytics workspace (LAQueryLogs)" \
	"LAQueryLogs | project TimeGenerated, ResponseCode, Query = substring(QueryText, 0, 80) | order by TimeGenerated desc | take 5" \
	"[].{Time:TimeGenerated,Response:ResponseCode,Query:Query}"

# The executions of the function app and the transactions of the storage account, read from the Azure Monitor metrics
# API: they need no diagnostic setting
show_metrics "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app" FunctionExecutionCount
show_metrics "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account" Transactions Ingress Egress

exit $EXIT_CODE
