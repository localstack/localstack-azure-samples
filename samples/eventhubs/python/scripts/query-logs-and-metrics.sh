#!/bin/bash

# Usage: query-logs-and-metrics.sh
#
# Calls the operations dashboard, then reads back what the diagnostic settings of the sample sent to its Log Analytics
# workspace: the HTTP requests, console output and platform events of the dashboard, the invocation records of the fraud
# detection function, the requests to the blobs of the storage account, the reads of the Key Vault secrets, the
# operations on the Event Hubs namespace, the exported platform metrics and the audit records of the queries run on the
# workspace. It ends with platform metrics read from the Azure Monitor metrics API. Run it after validate.sh, which reads
# the secrets, and run-pipeline.sh, which sends the payments.
#
# Before it reads the records of the key vault, it reads the secrets again: on Azure the records of a new diagnostic
# setting's first minutes, validate.sh's reads among them, can be lost.
#
# The records reach the workspace within seconds on the emulator, and the platform metrics once their one-minute window
# is over. On Azure they take minutes, and the first records of a new diagnostic setting can take up to 90 minutes, so
# every query is retried: raise RETRY_COUNT there.
# The platform metrics are the exception on Azure, which exports them late and irregularly: there the script reads
# them once, shows those that arrived and notes how many are still missing, without failing.

# Variables (the same defaults and environment overrides as deploy.sh)
PREFIX="${PREFIX:-local}"
SUFFIX='payments'
RESOURCE_GROUP_NAME="${PREFIX}-eventhubs-rg"
LOG_ANALYTICS_NAME="${PREFIX}-eh-logs"
WEB_APP_NAME="${PREFIX}-eh-dashboard"
FUNCTION_APP_NAME="${PREFIX}-eh-fraud-func"
STORAGE_ACCOUNT_NAME="${PREFIX}ehstorage${SUFFIX:0:4}"
KEY_VAULT_NAME="${PREFIX}ehkv${SUFFIX:0:4}"
EVENTHUB_NAMESPACE_NAME="${PREFIX}-ehns-${SUFFIX}"
DASHBOARD_CALLS="${DASHBOARD_CALLS:-3}"
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

# Run a KQL query on the Log Analytics workspace once and print the records it returns as a table, or say that there
# are none: for records that may not have arrived yet
# $1: what the query reads
# $2: the KQL query
# $3: the JMESPath projection that names and orders the columns of the table
# $4: what it means when there are no records
show_workspace_records() {
	local description=$1
	local query=$2
	local columns=$3
	local when_empty=$4
	local records

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
	elif [[ $records == 0 ]]; then
		echo "$when_empty"
	else
		az monitor log-analytics query \
			--workspace "$WORKSPACE_ID" \
			--analytics-query "$query" \
			--query "$columns" \
			--output table \
			--only-show-errors
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

# Get the resource ids of the function app and of its plan, of the storage account, of the key vault, of the Event Hubs
# namespace and of the Log Analytics workspace
echo "Retrieving the resource ids of the other resources of the sample..."
FUNCTION_APP_ID=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
FUNCTION_PLAN_ID=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query appServicePlanId --output tsv --only-show-errors)
STORAGE_ACCOUNT_ID=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
KEY_VAULT_ID=$(az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
EVENTHUB_NAMESPACE_ID=$(az eventhubs namespace show --name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show --workspace-name "$LOG_ANALYTICS_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)

if [[ -n $FUNCTION_APP_ID && -n $FUNCTION_PLAN_ID && -n $STORAGE_ACCOUNT_ID && -n $KEY_VAULT_ID && -n $EVENTHUB_NAMESPACE_ID && -n $LOG_ANALYTICS_ID ]]; then
	echo "Resource ids of the other resources of the sample successfully retrieved"
else
	echo "Failed to retrieve the resource ids of the other resources of the sample"
	exit 1
fi

# Show where the diagnostic settings send the logs and metrics of every resource of the sample that has them
show_diagnostic_settings "$WEB_APP_ID" "[$WEB_APP_NAME] web app"
show_diagnostic_settings "$APP_SERVICE_PLAN_ID" "App Service plan of the [$WEB_APP_NAME] web app"
show_diagnostic_settings "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app"
show_diagnostic_settings "$FUNCTION_PLAN_ID" "plan of the [$FUNCTION_APP_NAME] function app"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account"
for SERVICE in blob queue table; do
	show_diagnostic_settings "$STORAGE_ACCOUNT_ID/${SERVICE}Services/default" "$SERVICE service of the [$STORAGE_ACCOUNT_NAME] storage account"
done
show_diagnostic_settings "$KEY_VAULT_ID" "[$KEY_VAULT_NAME] key vault"
show_diagnostic_settings "$EVENTHUB_NAMESPACE_ID" "[$EVENTHUB_NAMESPACE_NAME] Event Hubs namespace"
show_diagnostic_settings "$LOG_ANALYTICS_ID" "[$LOG_ANALYTICS_NAME] Log Analytics workspace"

# Wait until the web app answers: on Azure the asynchronous zip deployment can still be building the app
echo -e "\nWaiting for the [$WEB_APP_NAME] web app to answer at [https://$WEB_APP_HOST_NAME/health]..."
ATTEMPT=1
while [ $ATTEMPT -le $RETRY_COUNT ]; do
	STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "https://$WEB_APP_HOST_NAME/health")

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

# Ask the dashboard for its overview, so that the request logs and metrics hold the requests of this run
echo "Calling the overview of the [$WEB_APP_NAME] web app [$DASHBOARD_CALLS] times..."
for CALL in $(seq 1 "$DASHBOARD_CALLS"); do
	STATUS_CODE=$(curl --max-time 60 --silent --output /dev/null --write-out "%{http_code}" "https://$WEB_APP_HOST_NAME/api/overview")
	echo "Call $CALL of $DASHBOARD_CALLS to the overview of the [$WEB_APP_NAME] web app answered with status code [$STATUS_CODE]"
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
# (FunctionAppLogs): the FraudDetector function, one invocation per batch of payments
query_workspace \
	"Records of the invocations per function (FunctionAppLogs)" \
	"FunctionAppLogs | where Category startswith 'Function.' | summarize Records = count() by FunctionName | order by FunctionName asc" \
	"[].{Function:FunctionName,Records:Records}"

# The requests to the blobs of the storage account, counted per operation and authentication: Event Hubs Capture writes
# the archives, the Functions host keeps its leases and checkpoints there, and the dashboard reads both (StorageBlobLogs,
# from the diagnostic setting of the blob service)
query_workspace \
	"Requests to the blobs of the [$STORAGE_ACCOUNT_NAME] storage account (StorageBlobLogs)" \
	"StorageBlobLogs | summarize Requests = count() by OperationName, AuthenticationType | order by Requests desc | take 10" \
	"[].{Operation:OperationName,Authentication:AuthenticationType,Requests:Requests}"

# Azure can drop for good the records of a new diagnostic setting's first minutes, and validate.sh reads the secrets
# right after the deployment, so they are read again here (their values are never printed)
for SECRET_NAME in eventhub-send-connection eventhub-listen-connection storage-connection; do
	echo "Reading the [$SECRET_NAME] secret of the [$KEY_VAULT_NAME] key vault..."
	az keyvault secret show \
		--vault-name "$KEY_VAULT_NAME" \
		--name "$SECRET_NAME" \
		--query id \
		--output tsv \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$SECRET_NAME] secret successfully read"
	else
		echo "Failed to read the [$SECRET_NAME] secret"
		EXIT_CODE=1
	fi
done

# The reads of the Key Vault secrets that hold the connection strings, those just above among them (AZKVAuditLogs)
query_workspace \
	"Secret reads in the [$KEY_VAULT_NAME] key vault (AZKVAuditLogs)" \
	"AZKVAuditLogs | where OperationName == 'SecretGet' | project TimeGenerated, OperationName, ResultSignature, RequestUri | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Operation:OperationName,Result:ResultSignature,Uri:RequestUri}"

# The operations on the Event Hubs namespace and its entities, such as creating an event hub (AZMSOperationalLogs).
# Which of them a deployment leaves depends on whether the diagnostic setting of the namespace existed when they ran, so
# the query runs once.
show_workspace_records \
	"Latest operations on the [$EVENTHUB_NAMESPACE_NAME] Event Hubs namespace (AZMSOperationalLogs)" \
	"AZMSOperationalLogs | project TimeGenerated, EventName, Status, Caller | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Event:EventName,Status:Status,Caller:Caller}" \
	"No records: the diagnostic setting of the namespace was created after its entities."

# The platform metrics the AllMetrics category of the diagnostic settings exports to the workspace (AzureMetrics), one
# record per metric and minute, exported once the minute is over. On Azure each resource's metrics start arriving at
# their own pace, so the query waits for the first of them and shows those that arrived.
query_metrics \
	"Platform metrics exported to the [$LOG_ANALYTICS_NAME] Log Analytics workspace (AzureMetrics)" \
	"AzureMetrics | where MetricName in ('Requests', 'Transactions', 'IncomingMessages') | summarize Total = sum(Total) by ResourceProvider, Resource, MetricName | order by ResourceProvider asc" \
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
show_metrics "$EVENTHUB_NAMESPACE_ID" "[$EVENTHUB_NAMESPACE_NAME] Event Hubs namespace" Total IncomingMessages OutgoingMessages CapturedMessages

exit $EXIT_CODE
