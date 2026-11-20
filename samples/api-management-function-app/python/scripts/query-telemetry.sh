#!/bin/bash

# Usage: query-telemetry.sh
#
# Calls the Inventory API through the API Management gateway with the subscription key, then reads back what the
# Functions host and the Python worker of the Function App behind it sent through the connection string of the
# Application Insights resource to its Log Analytics workspace: the invocations of the functions (AppRequests), the log
# records of the functions, among them the warning of an item that doesn't exist (AppTraces), the InventoryItemServed
# custom event of each item the backend served (AppEvents), the custom metric that counts them per SKU (AppMetrics),
# and the exceptions the functions logged, if any (AppExceptions). The API allows ten calls a minute per subscription,
# so the script makes five and waits as long as the gateway asks when it answers 429.
#
# The records reach the workspace within seconds on the emulator. On Azure they take minutes, so every query is
# retried: raise RETRY_COUNT there.

# Variables (the same defaults and environment overrides as the deploy scripts)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
APIM_NAME="${PREFIX}-inventory-apim-${SUFFIX}"
APIM_API_VERSION='2022-08-01'
API_PATH='inventory'
APIM_SUBSCRIPTION_ID='partner-subscription'
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

# Get the resource id of the API Management service
echo "Retrieving the resource id of the [$APIM_NAME] API Management service..."
APIM_ID=$(az apim show \
	--name "$APIM_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

if [[ -n $APIM_ID ]]; then
	echo "Resource id of the [$APIM_NAME] API Management service successfully retrieved"
else
	echo "Failed to retrieve the resource id of the [$APIM_NAME] API Management service"
	exit 1
fi

# Where the gateway answers: Azure's gatewayUrl, or the emulator's local alias (the emulator also claims the
# *.azure-api.net name, but it only resolves once LocalStack's DNS is in front of the machine)
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	GATEWAY_URL="http://${APIM_NAME}.apim.azure.localhost.localstack.cloud:4566"
else
	GATEWAY_URL=$(az apim show \
		--name "$APIM_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query gatewayUrl \
		--output tsv \
		--only-show-errors)
fi
API_URL="$GATEWAY_URL/$API_PATH"

# Read the key of the subscription the calls present (never printed)
echo "Reading the [$APIM_SUBSCRIPTION_ID] subscription key..."
KEY=$(az rest --method post \
	--url "$APIM_ID/subscriptions/$APIM_SUBSCRIPTION_ID/listSecrets?api-version=$APIM_API_VERSION" \
	--query primaryKey \
	--output tsv)

if [[ -n $KEY ]]; then
	echo "[$APIM_SUBSCRIPTION_ID] subscription key successfully retrieved"
else
	echo "Failed to retrieve the [$APIM_SUBSCRIPTION_ID] subscription key"
	exit 1
fi

# Call the gateway with the subscription key, waiting as long as the gateway asks when it answers 429 (the API allows
# ten calls a minute per subscription)
# $1: the URL
call_api() {
	local url=$1
	local headers_file
	headers_file=$(mktemp)
	STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --dump-header "$headers_file" --write-out "%{http_code}" \
		--header "Ocp-Apim-Subscription-Key: $KEY" "$url")
	if [[ $STATUS_CODE == 429 ]]; then
		RETRY_AFTER=$(grep -i "^retry-after:" "$headers_file" | tr -d '\r' | awk '{print $2}')
		RETRY_AFTER=${RETRY_AFTER:-10}
		[[ $RETRY_AFTER -lt 1 ]] && RETRY_AFTER=1
		[[ $RETRY_AFTER -gt 60 ]] && RETRY_AFTER=60
		echo "Rate limited by the gateway: waiting [$RETRY_AFTER] seconds as asked..."
		sleep "$RETRY_AFTER"
		STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" \
			--header "Ocp-Apim-Subscription-Key: $KEY" "$url")
	fi
	rm -f "$headers_file"
}

# Wait until the API answers through the gateway: on Azure the Function App behind it starts when its first request
# arrives, and the deploy scripts upload its code asynchronously
echo "Waiting for the API to answer at [$API_URL/items]..."
ATTEMPT=1
while [ $ATTEMPT -le $RETRY_COUNT ]; do
	call_api "$API_URL/items"

	if [[ $STATUS_CODE == 200 ]]; then
		echo "The API answered with status code [$STATUS_CODE]"
		break
	fi

	if [ $ATTEMPT -lt $RETRY_COUNT ]; then
		echo "Attempt $ATTEMPT of $RETRY_COUNT: the API answered with status code [$STATUS_CODE]. Waiting [$SLEEP] seconds before retry..."
		sleep $SLEEP
	fi
	ATTEMPT=$((ATTEMPT + 1))
done

if [[ $STATUS_CODE != 200 ]]; then
	echo "ERROR: the API answered with status code [$STATUS_CODE] after $RETRY_COUNT attempts"
	exit 1
fi

# Read three items and one that doesn't exist, so that the tables hold the requests of this run: the backend sends an
# InventoryItemServed custom event for each item it serves and logs a warning for the missing one
for ROUTE_PATH in /items/1 /items/2 /items/3 /items/99; do
	call_api "$API_URL$ROUTE_PATH"
	echo "Call to [$ROUTE_PATH] answered with status code [$STATUS_CODE]"
done

# The invocations of the functions, counted per function (AppRequests)
query_workspace \
	"Invocations per function (AppRequests)" \
	"AppRequests | summarize Invocations = count(), Failed = countif(Success == false) by Name | order by Name asc" \
	"[].{Function:Name,Invocations:Invocations,Failed:Failed}"

# The log records of the functions (AppTraces): the warning of the missing item has severity 2
query_workspace \
	"Latest log records of the Function App (AppTraces)" \
	"AppTraces | project TimeGenerated, Message, SeverityLevel | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Message:Message,Severity:SeverityLevel}"

# The InventoryItemServed custom events, counted per SKU (AppEvents)
query_workspace \
	"InventoryItemServed custom events, per SKU (AppEvents)" \
	"AppEvents | where Name == 'InventoryItemServed' | summarize Events = count() by Sku = tostring(Properties['inventory.sku']) | order by Sku asc" \
	"[].{Sku:Sku,Events:Events}"

# The custom metric that counts the inventory items served per SKU, exported once a minute (AppMetrics)
query_workspace \
	"Custom metric of the inventory items served (AppMetrics)" \
	"AppMetrics | where Name == 'inventory_items_served' | summarize Total = sum(Sum) by Name, Sku = tostring(Properties['sku']) | order by Sku asc" \
	"[].{Metric:Name,Sku:Sku,Total:Total}"

# The exceptions the functions logged with their stack trace (AppExceptions)
show_workspace_records \
	"Latest exceptions of the Function App (AppExceptions)" \
	"AppExceptions | project TimeGenerated, ExceptionType, OuterMessage | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Exception:ExceptionType,Message:OuterMessage}" \
	"No exceptions: the functions logged none."

exit $EXIT_CODE
