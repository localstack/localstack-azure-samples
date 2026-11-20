#!/bin/bash

# Usage: query-logs-and-metrics.sh
#
# Reads back what the diagnostic settings of the sample sent to its Log Analytics workspace: the records the Functions
# host writes for each invocation of the functions (FunctionAppLogs), first those of the GreetingRequester timer
# function, which runs when the host starts and then every 10 seconds, the exported platform metrics of the function app
# and of its App Service plan (AzureMetrics), the requests to the blobs, the queues and the tables of the storage
# account (StorageBlobLogs, StorageQueueLogs, StorageTableLogs) and the transaction metrics of the storage account and
# of its services, the runtime audit and operational logs of the Service Bus namespace (AZMSRunTimeAuditLogs,
# AZMSOperationalLogs) and its exported metrics, and the audit records of the queries run on the workspace
# (LAQueryLogs). It ends with the executions of the function app, the transactions of the storage account and the
# messages of the namespace read from the Azure Monitor metrics API. The timers keep the function app busy by
# themselves, so the script calls nothing.
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
FUNCTION_APP_NAME="${PREFIX}-func-${SUFFIX}"
TIMER_FUNCTION_NAME="GreetingRequester"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
SERVICE_BUS_NAMESPACE="${PREFIX}-service-bus-${SUFFIX}"
VIRTUAL_NETWORK_NAME="${PREFIX}-vnet-${SUFFIX}"
NAT_GATEWAY_NAME="${PREFIX}-nat-gateway-${SUFFIX}"
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

# Get the tier of the App Service plan: the Azure CLI shows it under properties since version 2.93.0, and at the top
# level before it
echo "Retrieving the tier of the App Service plan of the [$FUNCTION_APP_NAME] function app..."
FUNCTION_APP_SKU=$(az functionapp show \
	--name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "properties.sku || sku" \
	--output tsv \
	--only-show-errors)

if [[ -n $FUNCTION_APP_SKU ]]; then
	echo "Tier [$FUNCTION_APP_SKU] of the App Service plan successfully retrieved"
else
	echo "Failed to retrieve the tier of the App Service plan of the [$FUNCTION_APP_NAME] function app"
	exit 1
fi

# The platform metric that counts the executions of the function app: OnDemandFunctionExecutionCount on the Flex
# Consumption plan, which doesn't define FunctionExecutionCount (Azure Functions monitoring data reference)
if [[ $FUNCTION_APP_SKU == "FlexConsumption" ]]; then
	EXECUTION_COUNT_METRIC="OnDemandFunctionExecutionCount"
else
	EXECUTION_COUNT_METRIC="FunctionExecutionCount"
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

# Get the resource id of the Service Bus namespace
echo "Retrieving the resource id of the [$SERVICE_BUS_NAMESPACE] Service Bus namespace..."
SERVICE_BUS_NAMESPACE_ID=$(az servicebus namespace show \
	--name "$SERVICE_BUS_NAMESPACE" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $SERVICE_BUS_NAMESPACE_ID ]]; then
	echo "Resource id [$SERVICE_BUS_NAMESPACE_ID] of the [$SERVICE_BUS_NAMESPACE] Service Bus namespace successfully retrieved"
else
	echo "Failed to retrieve the resource id of the [$SERVICE_BUS_NAMESPACE] Service Bus namespace"
	exit 1
fi

# Get the resource ids of the virtual network, of the network security groups of its subnets, of the NAT Gateway and of
# its public IP: a public IP prefix with the scripts and Bicep, a public IP address with Terraform
echo "Retrieving the resource ids of the [$VIRTUAL_NETWORK_NAME] virtual network, of the network security groups of its subnets, of the [$NAT_GATEWAY_NAME] NAT Gateway and of its public IP..."
VIRTUAL_NETWORK_ID=$(az network vnet show \
	--name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
NETWORK_SECURITY_GROUP_IDS=$(az network vnet show \
	--name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "subnets[?networkSecurityGroup].networkSecurityGroup.id" \
	--output tsv \
	--only-show-errors)
NAT_GATEWAY_ID=$(az network nat gateway show \
	--name "$NAT_GATEWAY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)
NAT_GATEWAY_PUBLIC_IP_ID=$(az network nat gateway show \
	--name "$NAT_GATEWAY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "publicIpPrefixes[0].id || publicIpAddresses[0].id" \
	--output tsv \
	--only-show-errors)

if [[ -n $VIRTUAL_NETWORK_ID && -n $NETWORK_SECURITY_GROUP_IDS && -n $NAT_GATEWAY_ID && -n $NAT_GATEWAY_PUBLIC_IP_ID ]]; then
	echo "Resource ids of the network resources successfully retrieved"
else
	echo "Failed to retrieve the resource ids of the network resources"
	exit 1
fi

# Show where the diagnostic settings send the logs and metrics of the resources
show_diagnostic_settings "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app"
show_diagnostic_settings "$APP_SERVICE_PLAN_ID" "App Service plan"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID/blobServices/default" "blob service of the [$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID/queueServices/default" "queue service of the [$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$STORAGE_ACCOUNT_ID/tableServices/default" "table service of the [$STORAGE_ACCOUNT_NAME] storage account"
show_diagnostic_settings "$SERVICE_BUS_NAMESPACE_ID" "[$SERVICE_BUS_NAMESPACE] Service Bus namespace"
show_diagnostic_settings "$VIRTUAL_NETWORK_ID" "[$VIRTUAL_NETWORK_NAME] virtual network"
for NETWORK_SECURITY_GROUP_ID in $NETWORK_SECURITY_GROUP_IDS; do
	show_diagnostic_settings "$NETWORK_SECURITY_GROUP_ID" "[${NETWORK_SECURITY_GROUP_ID##*/}] network security group"
done
show_diagnostic_settings "$NAT_GATEWAY_ID" "[$NAT_GATEWAY_NAME] NAT Gateway"
show_diagnostic_settings "$NAT_GATEWAY_PUBLIC_IP_ID" "public IP of the [$NAT_GATEWAY_NAME] NAT Gateway"
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

# The platform metrics of the function app that the AllMetrics category of its diagnostic setting exports to the workspace
# (AzureMetrics), one record per metric and minute, exported once the minute is over. Azure exports the memory, I/O and
# HTTP metrics of the function app, such as MemoryWorkingSet, but not its executions (FunctionExecutionCount), which only
# the metrics API serves (see the end of the script). A function app on the Flex Consumption plan defines fewer metrics,
# and Azure exports its executions too (OnDemandFunctionExecutionCount).
query_metrics \
	"Platform metrics of the [$FUNCTION_APP_NAME] function app exported to the workspace (AzureMetrics)" \
	"AzureMetrics | where _ResourceId =~ '$FUNCTION_APP_ID' | summarize Minutes = count(), Total = sum(Total) by Resource, MetricName | order by MetricName asc" \
	"[].{Resource:Resource,Metric:MetricName,Minutes:Minutes,Total:Total}"

# The platform metrics of the App Service plan that the AllMetrics category of its diagnostic setting exports to the
# workspace (AzureMetrics): the average use of the CPU and of the memory of its instances in each minute. Azure records
# no metric for a Flex Consumption plan, whose apps' instances the platform runs, so on that plan the query runs once
# instead of waiting for records.
if [[ $FUNCTION_APP_SKU == "FlexConsumption" ]]; then
	show_workspace_records \
		"Platform metrics of the App Service plan exported to the workspace (AzureMetrics)" \
		"AzureMetrics | where _ResourceId =~ '$APP_SERVICE_PLAN_ID' | summarize Minutes = count(), Average = avg(Average) by Resource, MetricName | order by MetricName asc" \
		"[].{Resource:Resource,Metric:MetricName,Minutes:Minutes,Average:Average}" \
		"No records: the Flex Consumption plan exported no platform metric."
else
	query_metrics \
		"Platform metrics of the App Service plan exported to the workspace (AzureMetrics)" \
		"AzureMetrics | where _ResourceId =~ '$APP_SERVICE_PLAN_ID' and MetricName in ('CpuPercentage', 'MemoryPercentage') | summarize Minutes = count(), Average = avg(Average) by Resource, MetricName | order by MetricName asc" \
		"[].{Resource:Resource,Metric:MetricName,Minutes:Minutes,Average:Average}"
fi

# The requests to the blobs of the storage account, from the diagnostic setting of the blob service: the Functions host
# keeps its locks and keys there and authenticates with the account key (AccountKey)
query_workspace \
	"Latest requests to the blobs of the [$STORAGE_ACCOUNT_NAME] storage account (StorageBlobLogs)" \
	"StorageBlobLogs | where AccountName =~ '$STORAGE_ACCOUNT_NAME' | project TimeGenerated, OperationName, StatusCode, AuthenticationType, ObjectKey | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Operation:OperationName,Status:StatusCode,Authentication:AuthenticationType,Object:ObjectKey}"

# The requests to the queues and the tables of the storage account, from the diagnostic settings of their services. The
# functions of this sample use neither, and the Functions host only for features the sample doesn't use, so the
# queries run once.
show_workspace_records \
	"Latest requests to the queues of the [$STORAGE_ACCOUNT_NAME] storage account (StorageQueueLogs)" \
	"StorageQueueLogs | where AccountName =~ '$STORAGE_ACCOUNT_NAME' | project TimeGenerated, OperationName, StatusCode, AuthenticationType, ObjectKey | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Operation:OperationName,Status:StatusCode,Authentication:AuthenticationType,Object:ObjectKey}" \
	"No records: nothing used the queues of the storage account."

show_workspace_records \
	"Latest requests to the tables of the [$STORAGE_ACCOUNT_NAME] storage account (StorageTableLogs)" \
	"StorageTableLogs | where AccountName =~ '$STORAGE_ACCOUNT_NAME' | project TimeGenerated, OperationName, StatusCode, AuthenticationType, ObjectKey | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Operation:OperationName,Status:StatusCode,Authentication:AuthenticationType,Object:ObjectKey}" \
	"No records: nothing used the tables of the storage account."

# The transaction metrics that the diagnostic settings of the storage account and of its services export to the
# workspace (AzureMetrics), one record per metric and minute for each of them: the account and its blob service at
# least, the services nothing used have none
query_metrics \
	"Transaction metrics of the [$STORAGE_ACCOUNT_NAME] storage account exported to the workspace (AzureMetrics)" \
	"AzureMetrics | where _ResourceId startswith '$STORAGE_ACCOUNT_ID' and MetricName == 'Transactions' | extend Scope = case(_ResourceId endswith '/blobServices/default', 'blob service', _ResourceId endswith '/queueServices/default', 'queue service', _ResourceId endswith '/tableServices/default', 'table service', 'storage account') | summarize Minutes = count(), Total = sum(Total) by Scope, MetricName | order by Scope asc" \
	"[].{Scope:Scope,Metric:MetricName,Minutes:Minutes,Total:Total}" \
	2

# The runtime audit and operational logs of the Service Bus namespace (AZMSRunTimeAuditLogs, AZMSOperationalLogs),
# which its diagnostic settings write to resource-specific tables. Which of them Azure writes depends on the tier of the
# namespace and on what changes it, so the queries run once.
show_workspace_records \
	"Latest runtime audit records of the [$SERVICE_BUS_NAMESPACE] Service Bus namespace (AZMSRunTimeAuditLogs)" \
	"AZMSRunTimeAuditLogs | project TimeGenerated, ActivityName, Status, Protocol, AuthType | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Activity:ActivityName,Status:Status,Protocol:Protocol,AuthType:AuthType}" \
	"No records: the namespace wrote no runtime audit log since its diagnostic settings were created."
show_workspace_records \
	"Latest operational records of the [$SERVICE_BUS_NAMESPACE] Service Bus namespace (AZMSOperationalLogs)" \
	"AZMSOperationalLogs | project TimeGenerated, EventName, Status, Caller | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Event:EventName,Status:Status,Caller:Caller}" \
	"No records: no operation changed the namespace since its diagnostic settings were created."

# The message metrics that the AllMetrics category of the namespace's diagnostic settings exports to the workspace
# (AzureMetrics)
query_metrics \
	"Message metrics of the [$SERVICE_BUS_NAMESPACE] Service Bus namespace exported to the workspace (AzureMetrics)" \
	"AzureMetrics | where ResourceProvider == 'MICROSOFT.SERVICEBUS' and MetricName in ('IncomingMessages', 'OutgoingMessages', 'IncomingRequests', 'CompleteMessage') | summarize Total = sum(Total) by MetricName | order by MetricName asc" \
	"[].{Metric:MetricName,Total:Total}"

# The audit records of the queries run on the workspace, among them the ones above (LAQueryLogs, from the diagnostic
# setting of the workspace itself)
query_workspace \
	"Latest queries run on the [$LOG_ANALYTICS_NAME] Log Analytics workspace (LAQueryLogs)" \
	"LAQueryLogs | project TimeGenerated, ResponseCode, Query = substring(QueryText, 0, 80) | order by TimeGenerated desc | take 5" \
	"[].{Time:TimeGenerated,Response:ResponseCode,Query:Query}"

# The executions of the function app and the transactions of the storage account, read from the Azure Monitor metrics
# API: they need no diagnostic setting
show_metrics "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app" "$EXECUTION_COUNT_METRIC"
show_metrics "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account" Transactions Ingress Egress
show_metrics "$SERVICE_BUS_NAMESPACE_ID" "[$SERVICE_BUS_NAMESPACE] Service Bus namespace" IncomingMessages OutgoingMessages

exit $EXIT_CODE
