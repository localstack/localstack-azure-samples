#!/bin/bash

# Usage: query-telemetry.sh
#
# Waits for the Front Door endpoint to answer, calls its catalog, status and whoami routes, then reads back what the
# Functions hosts and the Python workers of the two Function Apps sent through the connection string of the Application
# Insights resource to its Log Analytics workspace: the invocations of the functions per Function App (AppRequests), the
# log records of the functions (AppTraces), the CatalogItemServed custom event of each catalog item an origin served
# (AppEvents), the custom metric that counts them per origin (AppMetrics), and the exceptions the functions logged, if
# any (AppExceptions). Front Door caches the catalog responses, so a repeated call can be served from its cache without
# reaching an origin.
#
# The records reach the workspace within seconds on the emulator. On Azure they take minutes, so every query is
# retried: raise RETRY_COUNT there.

# Variables (the same defaults and environment overrides as the deploy scripts)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
PROFILE_NAME="${PREFIX}-catalog-afd-${SUFFIX}"
ENDPOINT_NAME="${PREFIX}-catalog-${SUFFIX}"
CALLS="${CALLS:-3}"
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
	echo "On Azure the first records of a new component can take several minutes: run the script again later or raise RETRY_COUNT."
	EXIT_CODE=1
}

# Run a KQL query on the Log Analytics workspace once and print the records it returns as a table, or say that there
# are none: for records that only an unexpected event produces
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

# The Front Door endpoint: on the emulator its local alias, on Azure the host name Azure assigned it
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	ENDPOINT_URL="http://${ENDPOINT_NAME}.afd.azure.localhost.localstack.cloud:4566"
else
	ENDPOINT_HOST_NAME=$(az afd endpoint show \
		--endpoint-name "$ENDPOINT_NAME" \
		--profile-name "$PROFILE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query hostName \
		--output tsv \
		--only-show-errors)
	ENDPOINT_URL="https://$ENDPOINT_HOST_NAME"
fi

# Wait until the endpoint answers: on Azure a new endpoint takes minutes to reach the edge, and the Function Apps start
# when their first request arrives
echo "Waiting for the [$ENDPOINT_NAME] Front Door endpoint to answer at [$ENDPOINT_URL/catalog/1]..."
ATTEMPT=1
while [ $ATTEMPT -le $RETRY_COUNT ]; do
	STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "$ENDPOINT_URL/catalog/1")

	if [[ $STATUS_CODE == 200 ]]; then
		echo "The [$ENDPOINT_NAME] Front Door endpoint answered with status code [$STATUS_CODE]"
		break
	fi

	if [ $ATTEMPT -lt $RETRY_COUNT ]; then
		echo "Attempt $ATTEMPT of $RETRY_COUNT: the [$ENDPOINT_NAME] Front Door endpoint answered with status code [$STATUS_CODE]. Waiting [$SLEEP] seconds before retry..."
		sleep $SLEEP
	fi
	ATTEMPT=$((ATTEMPT + 1))
done

if [[ $STATUS_CODE != 200 ]]; then
	echo "ERROR: the [$ENDPOINT_NAME] Front Door endpoint answered with status code [$STATUS_CODE] after $RETRY_COUNT attempts"
	exit 1
fi

# Call the routes of the endpoint, so that the tables hold the requests of this run
echo "Calling the catalog, status and whoami routes of the [$ENDPOINT_NAME] Front Door endpoint [$CALLS] times each..."
for CALL in $(seq 1 "$CALLS"); do
	for ROUTE_PATH in /catalog/1 /catalog/2 /catalog/3 /api/status /whoami; do
		STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "$ENDPOINT_URL$ROUTE_PATH")
		echo "Call $CALL of $CALLS to [$ROUTE_PATH] answered with status code [$STATUS_CODE]"
	done
done

# The invocations of the functions, counted per Function App (AppRoleName) and function (AppRequests)
query_workspace \
	"Invocations per Function App and function (AppRequests)" \
	"AppRequests | summarize Invocations = count(), Failed = countif(Success == false) by AppRoleName, Name | order by AppRoleName asc, Name asc" \
	"[].{App:AppRoleName,Function:Name,Invocations:Invocations,Failed:Failed}"

# The log records of the functions and of the Functions host (AppTraces)
query_workspace \
	"Latest log records of the two Function Apps (AppTraces)" \
	"AppTraces | project TimeGenerated, Message, SeverityLevel | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Message:Message,Severity:SeverityLevel}"

# The CatalogItemServed custom events, counted per origin and catalog item (AppEvents)
query_workspace \
	"CatalogItemServed custom events, per origin and item (AppEvents)" \
	"AppEvents | where Name == 'CatalogItemServed' | summarize Events = count() by Origin = tostring(Properties['origin.name']), Sku = tostring(Properties['catalog.sku']) | order by Origin asc, Sku asc" \
	"[].{Origin:Origin,Sku:Sku,Events:Events}"

# The custom metric that counts the catalog items each origin served, exported once a minute (AppMetrics)
query_workspace \
	"Custom metric of the catalog items served (AppMetrics)" \
	"AppMetrics | where Name == 'catalog_items_served' | summarize Total = sum(Sum) by Name, Origin = tostring(Properties['origin']) | order by Origin asc" \
	"[].{Metric:Name,Origin:Origin,Total:Total}"

# The exceptions the functions logged with their stack trace (AppExceptions)
show_workspace_records \
	"Latest exceptions of the two Function Apps (AppExceptions)" \
	"AppExceptions | project TimeGenerated, ExceptionType, OuterMessage | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Exception:ExceptionType,Message:OuterMessage}" \
	"No exceptions: the functions logged none."

exit $EXIT_CODE
