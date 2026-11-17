#!/bin/bash

# Usage: query-logs-and-metrics.sh
#
# Calls the web app, then reads back what the diagnostic settings of the sample sent to its Log Analytics workspace:
# the HTTP requests, console output and platform events of the web app, the invocation records of the functions, the
# requests to the links table and to the QR jobs queue, the reads of the Key Vault secrets, the PostgreSQL server log,
# the exported platform metrics and the audit records of the queries run on the workspace. It ends with platform metrics
# read from the Azure Monitor metrics API. Run it after query-telemetry.sh or call-web-app.sh, which shorten and follow a
# link.
#
# The records reach the workspace within seconds on the emulator, and the platform metrics once their one-minute window
# is over. On Azure they take minutes, and the first records of a new diagnostic setting can take up to 90 minutes, so
# every query is retried: raise RETRY_COUNT there.

# Variables (the same defaults and environment overrides as deploy.sh)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOG_ANALYTICS_NAME="${PREFIX}-urlshort-log-analytics-${SUFFIX}"
WEB_APP_NAME="${PREFIX}-urlshort-webapp-${SUFFIX}"
FUNCTION_APP_NAME="${PREFIX}-urlshort-functionapp-${SUFFIX}"
STORAGE_ACCOUNT_NAME="${PREFIX}urlshortstorage${SUFFIX}"
KEY_VAULT_NAME="${PREFIX}-urlshort-kv-${SUFFIX}"
POSTGRES_SERVER_NAME="${PREFIX}-urlshort-pgflex-${SUFFIX}"
SERVICEBUS_NAMESPACE_NAME="${PREFIX}-urlshort-sb-ns-${SUFFIX}"
WEB_APP_CALLS="${WEB_APP_CALLS:-5}"
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
		--query "[].{Name:name,Destination:logAnalyticsDestinationType,Logs:join(', ', logs[?enabled].category),Metrics:join(', ', metrics[?enabled].category)}" \
		--output table \
		--only-show-errors

	if [[ $? != 0 ]]; then
		echo "ERROR: failed to read the diagnostic settings of the $description"
		EXIT_CODE=1
	fi
}

# Show the platform metrics of a resource in the last hour, read from the Azure Monitor metrics API
# $1: the resource id
# $2: the resource description
# $3: the aggregation the metrics support (Total, Count, ...)
# $4...: the metric names
show_metrics() {
	local resource_id=$1
	local description=$2
	local aggregation=$3
	local field
	field=$(echo "$aggregation" | tr '[:upper:]' '[:lower:]')
	shift 3

	echo -e "\nPlatform metrics of the $description in the last hour:\n"
	az monitor metrics list \
		--resource "$resource_id" \
		--metrics "$@" \
		--interval PT1M \
		--aggregation "$aggregation" \
		--offset 1h \
		--query "value[].{Metric:name.value,Unit:unit,$aggregation:sum(timeseries[].data[].$field)}" \
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

# Get the resource id, the default host name and the App Service plan of the web app
echo "Retrieving the resource id, the default host name and the App Service plan of the [$WEB_APP_NAME] web app..."
WEB_APP_ID=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
WEB_APP_HOST_NAME=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query defaultHostName \
	--output tsv \
	--only-show-errors)
APP_SERVICE_PLAN_ID=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query appServicePlanId \
	--output tsv \
	--only-show-errors)

if [[ -n $WEB_APP_ID && -n $WEB_APP_HOST_NAME && -n $APP_SERVICE_PLAN_ID ]]; then
	echo "Resource id, default host name [$WEB_APP_HOST_NAME] and App Service plan of the [$WEB_APP_NAME] web app successfully retrieved"
else
	echo "Failed to retrieve the resource id, the default host name and the App Service plan of the [$WEB_APP_NAME] web app"
	exit 1
fi

# Get the resource ids of the function app, of the storage account, of the key vault, of the PostgreSQL flexible
# server, of the Service Bus namespace and of the Log Analytics workspace
echo "Retrieving the resource ids of the other resources of the sample..."
FUNCTION_APP_ID=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
STORAGE_ACCOUNT_ID=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
KEY_VAULT_ID=$(az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
POSTGRES_SERVER_ID=$(az postgres flexible-server show --name "$POSTGRES_SERVER_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
SERVICEBUS_NAMESPACE_ID=$(az servicebus namespace show --name "$SERVICEBUS_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show --workspace-name "$LOG_ANALYTICS_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)

if [[ -n $FUNCTION_APP_ID && -n $STORAGE_ACCOUNT_ID && -n $KEY_VAULT_ID && -n $POSTGRES_SERVER_ID && -n $SERVICEBUS_NAMESPACE_ID && -n $LOG_ANALYTICS_ID ]]; then
	echo "Resource ids of the other resources of the sample successfully retrieved"
else
	echo "Failed to retrieve the resource ids of the other resources of the sample"
	exit 1
fi

# Show where the diagnostic settings send the logs and metrics of every resource of the sample that has them
show_diagnostic_settings "$WEB_APP_ID" "[$WEB_APP_NAME] web app"
show_diagnostic_settings "$APP_SERVICE_PLAN_ID" "App Service plan of the [$WEB_APP_NAME] web app"
show_diagnostic_settings "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account"
for SERVICE in blob queue table; do
	show_diagnostic_settings "$STORAGE_ACCOUNT_ID/${SERVICE}Services/default" "$SERVICE service of the [$STORAGE_ACCOUNT_NAME] storage account"
done
show_diagnostic_settings "$KEY_VAULT_ID" "[$KEY_VAULT_NAME] key vault"
show_diagnostic_settings "$POSTGRES_SERVER_ID" "[$POSTGRES_SERVER_NAME] PostgreSQL flexible server"
show_diagnostic_settings "$SERVICEBUS_NAMESPACE_ID" "[$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace"
show_diagnostic_settings "$LOG_ANALYTICS_ID" "[$LOG_ANALYTICS_NAME] Log Analytics workspace"

# Wait until the web app answers: on Azure the asynchronous zip deployment can still be building the app
echo -e "\nWaiting for the [$WEB_APP_NAME] web app to answer at [http://$WEB_APP_HOST_NAME/]..."
ATTEMPT=1
while [ $ATTEMPT -le $RETRY_COUNT ]; do
	STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "http://$WEB_APP_HOST_NAME/")

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
	STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "http://$WEB_APP_HOST_NAME/")
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

# The records the Functions host writes when an invocation of a function starts and completes, counted per function
# (FunctionAppLogs): the AbuseScan and QrGenerator functions of the worker
query_workspace \
	"Records of the invocations per function (FunctionAppLogs)" \
	"FunctionAppLogs | where Category startswith 'Function.' | summarize Records = count() by FunctionName | order by FunctionName asc" \
	"[].{Function:FunctionName,Records:Records}"

# The requests to the links table, counted per operation and authentication: the web app's, with its managed identity
# (OAuth) (StorageTableLogs)
query_workspace \
	"Requests to the tables of the [$STORAGE_ACCOUNT_NAME] storage account (StorageTableLogs)" \
	"StorageTableLogs | summarize Requests = count() by OperationName, AuthenticationType | order by Requests desc | take 10" \
	"[].{Operation:OperationName,Authentication:AuthenticationType,Requests:Requests}"

# The requests to the QR jobs queue: the web app sends a message with its managed identity (OAuth), the queue trigger
# of the worker reads it with the account key (AccountKey) (StorageQueueLogs)
query_workspace \
	"Requests to the queues of the [$STORAGE_ACCOUNT_NAME] storage account (StorageQueueLogs)" \
	"StorageQueueLogs | summarize Requests = count() by OperationName, AuthenticationType | order by Requests desc | take 10" \
	"[].{Operation:OperationName,Authentication:AuthenticationType,Requests:Requests}"

# The reads of the Key Vault secrets: the web app reads the link-signing key and the PostgreSQL connection string once,
# when it first needs them (AZKVAuditLogs)
query_workspace \
	"Secret reads in the [$KEY_VAULT_NAME] key vault (AZKVAuditLogs)" \
	"AZKVAuditLogs | where OperationName == 'SecretGet' | project TimeGenerated, OperationName, ResultSignature, RequestUri | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Operation:OperationName,Result:ResultSignature,Uri:RequestUri}"

# The server log of the PostgreSQL flexible server, with the connections of the web app that record the clicks
# (PGSQLServerLogs)
query_workspace \
	"Latest records of the [$POSTGRES_SERVER_NAME] PostgreSQL server log (PGSQLServerLogs)" \
	"PGSQLServerLogs | project TimeGenerated, ErrorLevel, Message = substring(Message, 0, 80) | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Level:ErrorLevel,Message:Message}"

# The platform metrics the AllMetrics category of the diagnostic settings exports to the workspace (AzureMetrics), one
# record per metric and minute, exported once the minute is over. On Azure each resource's metrics start arriving at
# their own pace, so the query waits for the first of them and shows those that arrived.
query_workspace \
	"Platform metrics exported to the [$LOG_ANALYTICS_NAME] Log Analytics workspace (AzureMetrics)" \
	"AzureMetrics | where MetricName in ('Requests', 'connections_succeeded') | summarize Total = sum(Total) by ResourceProvider, Resource, MetricName | order by ResourceProvider asc" \
	"[].{Provider:ResourceProvider,Resource:Resource,Metric:MetricName,Total:Total}"

# The audit records of the queries run on the workspace, among them the ones above (LAQueryLogs, from the diagnostic
# setting of the workspace itself)
query_workspace \
	"Latest queries run on the [$LOG_ANALYTICS_NAME] Log Analytics workspace (LAQueryLogs)" \
	"LAQueryLogs | project TimeGenerated, ResponseCode, Query = substring(QueryText, 0, 80) | order by TimeGenerated desc | take 5" \
	"[].{Time:TimeGenerated,Response:ResponseCode,Query:Query}"

# The same platform metrics, read from the Azure Monitor metrics API: they need no diagnostic setting
show_metrics "$WEB_APP_ID" "[$WEB_APP_NAME] web app" Total Requests Http2xx Http4xx Http5xx BytesReceived BytesSent
show_metrics "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app" Total FunctionExecutionCount
show_metrics "$SERVICEBUS_NAMESPACE_ID" "[$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace" Total IncomingMessages OutgoingMessages
show_metrics "$POSTGRES_SERVER_ID" "[$POSTGRES_SERVER_NAME] PostgreSQL flexible server" Total connections_succeeded

exit $EXIT_CODE
