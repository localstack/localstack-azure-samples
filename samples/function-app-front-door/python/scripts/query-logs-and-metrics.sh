#!/bin/bash

# Usage: query-logs-and-metrics.sh
#
# Reads back what the diagnostic settings of the sample sent to its Log Analytics workspace: the records the Functions
# hosts of the two Function Apps write for each invocation (FunctionAppLogs), the requests the Front Door endpoint
# served, with the origin that answered and the cache status (FrontDoorAccessLog, in AzureDiagnostics), the requests of
# the Functions hosts to the blobs of their storage accounts (StorageBlobLogs), the exported platform metrics
# (AzureMetrics), and the audit records of the queries run on the workspace (LAQueryLogs). It ends with the executions
# of the Function Apps and the requests of the endpoint read from the Azure Monitor metrics API. Run it after query-
# telemetry.sh or call-front-door.sh, which call the endpoint.
#
# The records reach the workspace within seconds on the emulator, and the metrics once their one-minute window is
# over. On Azure they take minutes, and the first records of a new diagnostic setting can take up to 90 minutes, so
# every query is retried: raise RETRY_COUNT there.
# The platform metrics are the exception on Azure, which exports them late and irregularly: there the script reads
# them once, shows those that arrived and notes how many are still missing, without failing.

# Variables (the same defaults and environment overrides as deploy.sh)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
APP_SERVICE_PLAN_NAME="${PREFIX}-catalog-app-service-plan-${SUFFIX}"
PRIMARY_FUNCTION_APP_NAME="${PREFIX}-catalog-primary-${SUFFIX}"
SECONDARY_FUNCTION_APP_NAME="${PREFIX}-catalog-secondary-${SUFFIX}"
PRIMARY_STORAGE_ACCOUNT_NAME="${PREFIX}catalogpri${SUFFIX}"
SECONDARY_STORAGE_ACCOUNT_NAME="${PREFIX}catalogsec${SUFFIX}"
PROFILE_NAME="${PREFIX}-catalog-afd-${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
RETRY_COUNT="${RETRY_COUNT:-30}"
SLEEP="${SLEEP:-10}"
EXIT_CODE=0
# The active az cloud: LocalStack when az talks to the emulator (lstk az start-interception), AzureCloud on Azure
ACTIVE_CLOUD=$(az cloud show --query name --output tsv --only-show-errors)

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

# Run a KQL query on the platform metrics that the diagnostic settings export to the workspace (AzureMetrics). The
# emulator exports them once their one-minute window is over, so there the query waits for every record it expects, as
# query_workspace does. Azure exports each resource's metrics late and irregularly, sometimes long after the diagnostic
# setting was created, so on Azure the query runs once, prints the records that arrived and notes how many are still
# missing, without failing the script.
# $1: what the query reads
# $2: the KQL query
# $3: the JMESPath projection that names and orders the columns of the table
# $4: the number of records the query expects (1 when not given)
query_metrics() {
	local description=$1
	local query=$2
	local columns=$3
	local expected_records=${4:-1}
	local records

	if [[ $ACTIVE_CLOUD == "LocalStack" ]]; then
		query_workspace "$description" "$query" "$columns" "$expected_records"
		return
	fi

	echo -e "\n$description:\n"
	records=$(az monitor log-analytics query \
		--workspace "$WORKSPACE_ID" \
		--analytics-query "$query" \
		--query "length(@)" \
		--output tsv \
		--only-show-errors)

	if [[ $? != 0 ]]; then
		echo "ERROR: the [$LOG_ANALYTICS_NAME] Log Analytics workspace did not answer the query"
		EXIT_CODE=1
		return
	fi

	if [[ $records -gt 0 ]]; then
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
	fi

	if [[ $records -lt $expected_records ]]; then
		echo "NOTE: [$records] of the [$expected_records] records expected have arrived so far. Azure exports platform metrics late, sometimes long after a diagnostic setting is created: run the script again later to see the others."
	fi
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

# Get the resource ids of the two Function Apps, of their storage accounts, of the App Service plan, of the Front Door
# profile and of the Log Analytics workspace
echo "Retrieving the resource ids of the resources of the sample..."
PRIMARY_FUNCTION_APP_ID=$(az functionapp show --name "$PRIMARY_FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
SECONDARY_FUNCTION_APP_ID=$(az functionapp show --name "$SECONDARY_FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
PRIMARY_STORAGE_ACCOUNT_ID=$(az storage account show --name "$PRIMARY_STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
SECONDARY_STORAGE_ACCOUNT_ID=$(az storage account show --name "$SECONDARY_STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
APP_SERVICE_PLAN_ID=$(az appservice plan show --name "$APP_SERVICE_PLAN_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
PROFILE_ID=$(az afd profile show --profile-name "$PROFILE_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP_NAME" --workspace-name "$LOG_ANALYTICS_NAME" --query id --output tsv --only-show-errors)

if [[ -n $PRIMARY_FUNCTION_APP_ID && -n $SECONDARY_FUNCTION_APP_ID && -n $PRIMARY_STORAGE_ACCOUNT_ID && -n $SECONDARY_STORAGE_ACCOUNT_ID && -n $APP_SERVICE_PLAN_ID && -n $PROFILE_ID && -n $LOG_ANALYTICS_ID ]]; then
	echo "Resource ids of the resources of the sample successfully retrieved"
else
	echo "Failed to retrieve the resource ids of the resources of the sample"
	exit 1
fi

# Show where the diagnostic settings send the logs and metrics of the resources
show_diagnostic_settings "$PRIMARY_FUNCTION_APP_ID" "[$PRIMARY_FUNCTION_APP_NAME] function app"
show_diagnostic_settings "$SECONDARY_FUNCTION_APP_ID" "[$SECONDARY_FUNCTION_APP_NAME] function app"
show_diagnostic_settings "$APP_SERVICE_PLAN_ID" "[$APP_SERVICE_PLAN_NAME] App Service plan"
for STORAGE_ACCOUNT_ID in "$PRIMARY_STORAGE_ACCOUNT_ID" "$SECONDARY_STORAGE_ACCOUNT_ID"; do
	STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_ID##*/}"
	show_diagnostic_settings "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account"
	for SERVICE in blob queue table; do
		show_diagnostic_settings "$STORAGE_ACCOUNT_ID/${SERVICE}Services/default" "$SERVICE service of the [$STORAGE_ACCOUNT_NAME] storage account"
	done
done
show_diagnostic_settings "$PROFILE_ID" "[$PROFILE_NAME] Front Door profile"
show_diagnostic_settings "$LOG_ANALYTICS_ID" "[$LOG_ANALYTICS_NAME] Log Analytics workspace"

# The records the Functions hosts write for the invocations of the functions, counted per Function App and function
# (FunctionAppLogs)
query_workspace \
	"Records of the invocations per Function App and function (FunctionAppLogs)" \
	"FunctionAppLogs | where Category startswith 'Function.' | summarize Records = count() by AppName, FunctionName | order by AppName asc, FunctionName asc" \
	"[].{App:AppName,Function:FunctionName,Records:Records}"

# The requests the Front Door endpoint served, with the route, the origin that answered and whether the cache served
# them (FrontDoorAccessLog). Front Door writes its logs to the AzureDiagnostics table only.
query_workspace \
	"Latest requests served by the Front Door endpoint (FrontDoorAccessLog, in AzureDiagnostics)" \
	"AzureDiagnostics | where Category == 'FrontDoorAccessLog' | project TimeGenerated, httpMethod_s, requestUri_s, httpStatusCode_s, routingRuleName_s, originName_s, cacheStatus_s | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Method:httpMethod_s,Uri:requestUri_s,Status:httpStatusCode_s,Route:routingRuleName_s,Origin:originName_s,Cache:cacheStatus_s}"

# The requests of the Functions hosts to the blobs of their storage accounts, where they keep their locks and keys
# (StorageBlobLogs)
query_workspace \
	"Latest requests to the blobs of the storage accounts (StorageBlobLogs)" \
	"StorageBlobLogs | project TimeGenerated, AccountName, OperationName, StatusCode, AuthenticationType | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Account:AccountName,Operation:OperationName,Status:StatusCode,Authentication:AuthenticationType}"

# The platform metrics the AllMetrics category of the diagnostic settings exports to the workspace (AzureMetrics), one
# record per metric and minute. On Azure each resource's metrics start arriving at their own pace:
# query_metrics shows those that arrived.
query_metrics \
	"Platform metrics exported to the [$LOG_ANALYTICS_NAME] Log Analytics workspace (AzureMetrics)" \
	"AzureMetrics | summarize Total = sum(Total) by ResourceProvider, Resource, MetricName | order by ResourceProvider asc, Resource asc, MetricName asc | take 20" \
	"[].{Provider:ResourceProvider,Resource:Resource,Metric:MetricName,Total:Total}"

# The audit records of the queries run on the workspace, among them the ones above (LAQueryLogs, from the diagnostic
# setting of the workspace itself)
query_workspace \
	"Latest queries run on the [$LOG_ANALYTICS_NAME] Log Analytics workspace (LAQueryLogs)" \
	"LAQueryLogs | project TimeGenerated, ResponseCode, Query = substring(QueryText, 0, 80) | order by TimeGenerated desc | take 5" \
	"[].{Time:TimeGenerated,Response:ResponseCode,Query:Query}"

# The executions of the Function Apps and the requests of the Front Door endpoint, read from the Azure Monitor metrics
# API: they need no diagnostic setting
show_metrics "$PRIMARY_FUNCTION_APP_ID" "[$PRIMARY_FUNCTION_APP_NAME] function app" FunctionExecutionCount
show_metrics "$SECONDARY_FUNCTION_APP_ID" "[$SECONDARY_FUNCTION_APP_NAME] function app" FunctionExecutionCount
show_metrics "$PROFILE_ID" "[$PROFILE_NAME] Front Door profile" RequestCount

exit $EXIT_CODE
