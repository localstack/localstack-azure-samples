#!/bin/bash

# Usage: query-telemetry.sh
#
# Reads back what the Functions host sent through the connection string of the Application Insights resource to its
# Log Analytics workspace: the invocations of the functions (AppRequests), first those of the CreateGame timer
# function, which runs when the host starts and then every minute, and the log records of the functions and of the
# host (AppTraces). The timer keeps the function app busy by itself, so the script calls nothing.
#
# The records reach the workspace within seconds on the emulator. On Azure they take minutes, so every query is
# retried: raise RETRY_COUNT there.

# Variables (the same defaults and environment overrides as the deploy scripts)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
FUNCTION_APP_NAME="${PREFIX}-functionapp-${SUFFIX}"
TIMER_FUNCTION_NAME="CreateGame"
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

# The runs of the timer function (AppRequests)
query_workspace \
	"Latest runs of the [$TIMER_FUNCTION_NAME] timer function of the [$FUNCTION_APP_NAME] function app (AppRequests)" \
	"AppRequests | where Name == '$TIMER_FUNCTION_NAME' | project TimeGenerated, Name, Success, ResultCode, DurationMs | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Name:Name,Success:Success,Result:ResultCode,DurationMs:DurationMs}"

# The invocations of every function, counted per function (AppRequests)
query_workspace \
	"Invocations per function of the [$FUNCTION_APP_NAME] function app (AppRequests)" \
	"AppRequests | summarize Invocations = count(), Failed = countif(Success == false) by Name | order by Name asc" \
	"[].{Function:Name,Invocations:Invocations,Failed:Failed}"

# The log records of the functions and of the Functions host (AppTraces)
query_workspace \
	"Latest log records of the [$FUNCTION_APP_NAME] function app (AppTraces)" \
	"AppTraces | project TimeGenerated, Message, SeverityLevel | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Message:Message,Severity:SeverityLevel}"

exit $EXIT_CODE
