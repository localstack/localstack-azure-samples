#!/bin/bash

# Usage: query-logs-and-metrics.sh
#
# Runs test.sh, which uploads a text file that the function processes, then reads back what the diagnostic settings of
# the sample sent to its Log Analytics workspace: the records the Functions host writes for each invocation of the
# function (FunctionAppLogs) and the exported platform metrics of the function app and of its App Service plan
# (AzureMetrics). It ends with the executions of the function app read from the Azure Monitor metrics API.
#
# The records reach the workspace within seconds on the emulator, and the metrics once their one-minute window is
# over. On Azure they take minutes, and the first records of a new diagnostic setting can take up to 90 minutes, so
# every query is retried: raise RETRY_COUNT there.

# Variables (the same defaults and environment overrides as the deploy scripts)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
FUNCTION_APP_NAME="${PREFIX}-functionapp-${SUFFIX}"
FUNCTION_NAME="ProcessTextFunction"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
RETRY_COUNT="${RETRY_COUNT:-30}"
SLEEP="${SLEEP:-10}"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

# Show where the diagnostic settings send the logs and metrics of the function app and of its App Service plan
show_diagnostic_settings "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app"
show_diagnostic_settings "$APP_SERVICE_PLAN_ID" "App Service plan"

# Invoke the function: test.sh uploads a text file to the input container and waits for the processed one
echo -e "\nInvoking the [$FUNCTION_NAME] function of the [$FUNCTION_APP_NAME] function app with test.sh..."
bash "$CURRENT_DIR/test.sh"

if [[ $? == 0 ]]; then
	echo "The [$FUNCTION_NAME] function processed the uploaded file"
else
	echo "ERROR: test.sh failed, so the [$FUNCTION_NAME] function did not run"
	exit 1
fi

# The records the Functions host writes when an invocation of the function starts and completes (FunctionAppLogs):
# their category names the function (Function.<name>)
query_workspace \
	"Latest records of the invocations of the [$FUNCTION_NAME] function (FunctionAppLogs)" \
	"FunctionAppLogs | where Category == 'Function.$FUNCTION_NAME' | project TimeGenerated, FunctionName, EventName, Level, Message | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Function:FunctionName,Event:EventName,Level:Level,Message:Message}" \
	2

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

# The executions of the function app, read from the Azure Monitor metrics API: they need no diagnostic setting
show_metrics "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app" FunctionExecutionCount

exit $EXIT_CODE
