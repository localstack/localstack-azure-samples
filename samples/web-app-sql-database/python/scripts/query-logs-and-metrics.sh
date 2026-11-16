#!/bin/bash

# Usage: query-logs-and-metrics.sh
#
# Calls the web app, then reads back what the diagnostic settings of the sample sent to its Log Analytics workspace:
# the HTTP requests, console output and platform events of the web app, the reads of the connection string secret in
# the key vault, the audit records of the statements run on the database, the exported platform metrics and the audit
# records of the queries run on the workspace. It ends with the same platform metrics read from the Azure Monitor
# metrics API.
#
# The records reach the workspace within seconds on the emulator, and the platform metrics once their one-minute window
# is over. On Azure they take minutes, and the first records of a new diagnostic setting can take up to 90 minutes, so
# every query is retried: raise RETRY_COUNT there.

# Variables (the same defaults and environment overrides as deploy.sh)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
SQL_SERVER_NAME="${PREFIX}-sqlserver-${SUFFIX}"
SQL_DATABASE_NAME='PlannerDB'
KEY_VAULT_NAME="${PREFIX}-kv-${SUFFIX}"
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

# Get the resource id of the database
echo "Retrieving the resource id of the [$SQL_DATABASE_NAME] database..."
SQL_DATABASE_ID=$(az sql db show \
	--name "$SQL_DATABASE_NAME" \
	--server "$SQL_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $SQL_DATABASE_ID ]]; then
	echo "Resource id [$SQL_DATABASE_ID] of the [$SQL_DATABASE_NAME] database successfully retrieved"
else
	echo "Failed to retrieve the resource id of the [$SQL_DATABASE_NAME] database"
	exit 1
fi

# Get the resource ids of the key vault and of the Log Analytics workspace
echo "Retrieving the resource ids of the [$KEY_VAULT_NAME] key vault and of the [$LOG_ANALYTICS_NAME] Log Analytics workspace..."
KEY_VAULT_ID=$(az keyvault show \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $KEY_VAULT_ID && -n $LOG_ANALYTICS_ID ]]; then
	echo "Resource ids of the key vault and of the Log Analytics workspace successfully retrieved"
else
	echo "Failed to retrieve the resource ids of the key vault and of the Log Analytics workspace"
	exit 1
fi

# Show where the diagnostic settings send the logs and metrics of every resource of the sample that has them
show_diagnostic_settings "$WEB_APP_ID" "[$WEB_APP_NAME] web app"
show_diagnostic_settings "$APP_SERVICE_PLAN_ID" "App Service plan of the [$WEB_APP_NAME] web app"
show_diagnostic_settings "$KEY_VAULT_ID" "[$KEY_VAULT_NAME] key vault"
# The Azure CLI script gives the audit category (SQLSecurityAuditEvents) a diagnostic setting of its own
show_diagnostic_settings "$SQL_DATABASE_ID" "[$SQL_DATABASE_NAME] database"
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

# The reads of the connection string secret: the app reads it once when it starts, so the query waits for the first
# one (AZKVAuditLogs)
query_workspace \
	"Secret reads in the [$KEY_VAULT_NAME] key vault (AZKVAuditLogs)" \
	"AZKVAuditLogs | where OperationName == 'SecretGet' | project TimeGenerated, OperationName, ResultSignature, RequestUri | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Operation:OperationName,Result:ResultSignature,Uri:RequestUri}"

# The audit records of the database: one for each batch run on it and each sign-in, among them the app's queries
# (SQLSecurityAuditEvents, in AzureDiagnostics: the database's categories have no resource-specific table)
query_workspace \
	"Latest audit records of the [$SQL_DATABASE_NAME] database (SQLSecurityAuditEvents, in AzureDiagnostics)" \
	"AzureDiagnostics | where Category == 'SQLSecurityAuditEvents' | project TimeGenerated, Action = action_name_s, Succeeded = succeeded_s, Application = column_ifexists('application_name_s', ''), Statement = substring(column_ifexists('statement_s', ''), 0, 80) | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Action:Action,Succeeded:Succeeded,Application:Application,Statement:Statement}"

# The platform metrics the AllMetrics category of the diagnostic settings exports to the workspace (AzureMetrics), one
# record per metric and minute, exported once the minute is over. On Azure each resource's metrics start arriving at
# their own pace, so the query waits for the first of them and shows those that arrived.
query_workspace \
	"Platform metrics exported to the [$LOG_ANALYTICS_NAME] Log Analytics workspace (AzureMetrics)" \
	"AzureMetrics | where MetricName in ('Requests', 'connection_successful') | summarize Total = sum(Total) by ResourceProvider, Resource, MetricName | order by ResourceProvider asc" \
	"[].{Provider:ResourceProvider,Resource:Resource,Metric:MetricName,Total:Total}"

# The audit records of the queries run on the workspace, among them the ones above (LAQueryLogs, from the diagnostic
# setting of the workspace itself)
query_workspace \
	"Latest queries run on the [$LOG_ANALYTICS_NAME] Log Analytics workspace (LAQueryLogs)" \
	"LAQueryLogs | project TimeGenerated, ResponseCode, Query = substring(QueryText, 0, 80) | order by TimeGenerated desc | take 5" \
	"[].{Time:TimeGenerated,Response:ResponseCode,Query:Query}"

# The same platform metrics, read from the Azure Monitor metrics API: they need no diagnostic setting
show_metrics "$WEB_APP_ID" "[$WEB_APP_NAME] web app" Total Requests Http2xx Http4xx Http5xx BytesReceived BytesSent
show_metrics "$SQL_DATABASE_ID" "[$SQL_DATABASE_NAME] database" Total connection_successful

exit $EXIT_CODE
