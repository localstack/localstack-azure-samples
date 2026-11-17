#!/bin/bash

# Usage: query-logs-and-metrics.sh
#
# Calls the web app, then reads back what the diagnostic settings of the sample sent to its Log Analytics workspace:
# the HTTP requests, console output and platform events of the web app, the exported platform metrics of the web app and
# of its App Service plan, the requests of the web app to the blobs of the storage account and the transaction metrics
# of the storage account and of its blob service, and the audit records of the queries run on the workspace. It ends
# with the platform metrics of the web app and of the storage account read from the Azure Monitor metrics API.
#
# The records reach the workspace within seconds on the emulator, and the metrics once their one-minute window is
# over. On Azure they take minutes, and the first records of a new diagnostic setting can take up to 90 minutes, so
# every query is retried: raise RETRY_COUNT there.
# The platform metrics are the exception on Azure, which exports them late and irregularly: there the script reads
# them once, shows those that arrived and notes how many are still missing, without failing.

# Variables (the same defaults and environment overrides as the deploy scripts)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
WEB_APP_CALLS="${WEB_APP_CALLS:-5}"
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

# Get the resource id of the App Service plan of the web app
echo "Retrieving the resource id of the App Service plan of the [$WEB_APP_NAME] web app..."
APP_SERVICE_PLAN_ID=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query appServicePlanId \
	--output tsv \
	--only-show-errors)

if [[ -n $APP_SERVICE_PLAN_ID ]]; then
	echo "Resource id [$APP_SERVICE_PLAN_ID] of the App Service plan successfully retrieved"
else
	echo "Failed to retrieve the resource id of the App Service plan of the [$WEB_APP_NAME] web app"
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

# Get the default host name of the web app
echo "Retrieving the default host name of the [$WEB_APP_NAME] web app..."
WEB_APP_HOST_NAME=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query defaultHostName \
	--output tsv \
	--only-show-errors)

if [[ -n $WEB_APP_HOST_NAME ]]; then
	echo "Default host name [$WEB_APP_HOST_NAME] of the [$WEB_APP_NAME] web app successfully retrieved"
else
	echo "Failed to retrieve the default host name of the [$WEB_APP_NAME] web app"
	exit 1
fi

# Show where the diagnostic settings send the logs and metrics of the resources
show_diagnostic_settings "$WEB_APP_ID" "[$WEB_APP_NAME] web app"
show_diagnostic_settings "$APP_SERVICE_PLAN_ID" "App Service plan"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID/blobServices/default" "blob service of the [$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$LOG_ANALYTICS_ID" "[$LOG_ANALYTICS_NAME] Log Analytics workspace"

# Wait until the web app answers: on Azure the asynchronous zip deployment can still be building the app
echo -e "\nWaiting for the [$WEB_APP_NAME] web app to answer at [https://$WEB_APP_HOST_NAME/]..."
ATTEMPT=1
while [ $ATTEMPT -le $RETRY_COUNT ]; do
	STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "https://$WEB_APP_HOST_NAME/")

	if [[ $STATUS_CODE == 200 ]]; then
		echo "The [$WEB_APP_NAME] web app answered with status code [$STATUS_CODE]"
		break
	else
		if [ $ATTEMPT -lt $RETRY_COUNT ]; then
			echo "Attempt $ATTEMPT of $RETRY_COUNT: the [$WEB_APP_NAME] web app answered with status code [$STATUS_CODE]. Waiting [$SLEEP] seconds before retry..."
			sleep $SLEEP
		fi
		ATTEMPT=$((ATTEMPT + 1))
	fi
done

if [[ $STATUS_CODE != 200 ]]; then
	echo "ERROR: the [$WEB_APP_NAME] web app did not answer with status code [200] after $RETRY_COUNT attempts"
	EXIT_CODE=1
fi

# Call the web app, so that the request logs and metrics hold the requests of this run
echo "Calling the [$WEB_APP_NAME] web app [$WEB_APP_CALLS] times..."
for CALL in $(seq 1 "$WEB_APP_CALLS"); do
	STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "https://$WEB_APP_HOST_NAME/")
	echo "Call $CALL of $WEB_APP_CALLS to the [$WEB_APP_NAME] web app answered with status code [$STATUS_CODE]"
done

# The requests the web app served (AppServiceHTTPLogs)
query_workspace \
	"Latest requests served by the [$WEB_APP_NAME] web app (AppServiceHTTPLogs)" \
	"AppServiceHTTPLogs | project TimeGenerated, CsMethod, CsUriStem, ScStatus, TimeTaken | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Method:CsMethod,Path:CsUriStem,Status:ScStatus,TimeTakenMs:TimeTaken}"

# The console output of the web app: the request lines of its server and the application's own log lines
# (AppServiceConsoleLogs). On Azure the lines a container writes while it starts can be missing when it started shortly
# after the diagnostic setting was created, so the query reads the latest lines, which the calls above produced.
query_workspace \
	"Latest console output of the [$WEB_APP_NAME] web app (AppServiceConsoleLogs)" \
	"AppServiceConsoleLogs | project TimeGenerated, ResultDescription | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Line:ResultDescription}"

# The container events of the web app (AppServicePlatformLogs)
query_workspace \
	"Latest platform events of the [$WEB_APP_NAME] web app (AppServicePlatformLogs)" \
	"AppServicePlatformLogs | project TimeGenerated, Level, Message | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Level:Level,Message:Message}"

# The platform metrics of the web app that the AllMetrics category of its diagnostic setting exports to the workspace
# (AzureMetrics), one record per metric and minute, exported once the minute is over
query_metrics \
	"Platform metrics of the [$WEB_APP_NAME] web app exported to the workspace (AzureMetrics)" \
	"AzureMetrics | where _ResourceId =~ '$WEB_APP_ID' and MetricName in ('Requests', 'Http2xx', 'BytesSent') | summarize Minutes = count(), Total = sum(Total) by Resource, MetricName | order by MetricName asc" \
	"[].{Resource:Resource,Metric:MetricName,Minutes:Minutes,Total:Total}"

# The platform metrics of the App Service plan that the AllMetrics category of its diagnostic setting exports to the
# workspace (AzureMetrics): the average use of the CPU and of the memory of its instances in each minute
query_metrics \
	"Platform metrics of the App Service plan exported to the workspace (AzureMetrics)" \
	"AzureMetrics | where _ResourceId =~ '$APP_SERVICE_PLAN_ID' and MetricName in ('CpuPercentage', 'MemoryPercentage') | summarize Minutes = count(), Average = avg(Average) by Resource, MetricName | order by MetricName asc" \
	"[].{Resource:Resource,Metric:MetricName,Minutes:Minutes,Average:Average}"

# The requests of the web app to the blobs of the storage account, which it authenticates with its managed identity
# (StorageBlobLogs, from the diagnostic setting of the blob service)
query_workspace \
	"Latest requests to the blobs of the [$STORAGE_ACCOUNT_NAME] storage account (StorageBlobLogs)" \
	"StorageBlobLogs | where AccountName =~ '$STORAGE_ACCOUNT_NAME' | project TimeGenerated, OperationName, StatusCode, AuthenticationType, ObjectKey | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Operation:OperationName,Status:StatusCode,Authentication:AuthenticationType,Object:ObjectKey}"

# The transaction metrics that the diagnostic settings of the storage account and of its blob service export to the
# workspace (AzureMetrics), one record per metric and minute for each of the two
query_metrics \
	"Transaction metrics of the [$STORAGE_ACCOUNT_NAME] storage account exported to the workspace (AzureMetrics)" \
	"AzureMetrics | where _ResourceId startswith '$STORAGE_ACCOUNT_ID' and MetricName == 'Transactions' | extend Scope = iff(_ResourceId endswith '/blobServices/default', 'blob service', 'storage account') | summarize Minutes = count(), Total = sum(Total) by Scope, MetricName | order by Scope asc" \
	"[].{Scope:Scope,Metric:MetricName,Minutes:Minutes,Total:Total}" \
	2

# The audit records of the queries run on the workspace, among them the ones above (LAQueryLogs, from the diagnostic
# setting of the workspace itself)
query_workspace \
	"Latest queries run on the [$LOG_ANALYTICS_NAME] Log Analytics workspace (LAQueryLogs)" \
	"LAQueryLogs | project TimeGenerated, ResponseCode, Query = substring(QueryText, 0, 80) | order by TimeGenerated desc | take 5" \
	"[].{Time:TimeGenerated,Response:ResponseCode,Query:Query}"

# The same platform metrics of the web app and of the storage account, read from the Azure Monitor metrics API: they
# need no diagnostic setting
show_metrics "$WEB_APP_ID" "[$WEB_APP_NAME] web app" Requests Http2xx Http4xx Http5xx BytesReceived BytesSent
show_metrics "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account" Transactions Ingress Egress

exit $EXIT_CODE
