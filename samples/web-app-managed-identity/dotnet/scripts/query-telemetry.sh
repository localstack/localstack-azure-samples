#!/bin/bash

# Usage: query-telemetry.sh
#
# Waits for the web app to answer (the deploy scripts upload it asynchronously), calls it, then reads back what the
# Microsoft OpenTelemetry Distro sent through the connection string of the Application Insights resource to its Log
# Analytics workspace: the requests the web app served (AppRequests), its calls to Blob Storage (AppDependencies) and
# the application's own log records (AppTraces).
#
# The records reach the workspace within seconds on the emulator. On Azure they take minutes, so the wait and every
# query are retried: raise RETRY_COUNT there.

# Variables (the same defaults and environment overrides as the deploy scripts)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
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

# Wait until the web app answers: the deployment builds it asynchronously, and only a running app sends telemetry
echo "Waiting for the [$WEB_APP_NAME] web app to answer..."
ATTEMPT=1
while [ $ATTEMPT -le $RETRY_COUNT ]; do
	STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "https://$WEB_APP_HOST_NAME/")

	if [[ $STATUS_CODE == 200 ]]; then
		echo "The [$WEB_APP_NAME] web app answered with status code [$STATUS_CODE]"
		break
	fi

	if [ $ATTEMPT -lt $RETRY_COUNT ]; then
		echo "Attempt $ATTEMPT of $RETRY_COUNT: the [$WEB_APP_NAME] web app answered with status code [$STATUS_CODE]. Waiting [$SLEEP] seconds before retry..."
		sleep $SLEEP
	fi
	ATTEMPT=$((ATTEMPT + 1))
done

if [[ $STATUS_CODE != 200 ]]; then
	echo "ERROR: the [$WEB_APP_NAME] web app answered with status code [$STATUS_CODE] after $RETRY_COUNT attempts"
	exit 1
fi

# Call the web app, so that AppRequests, AppDependencies and AppTraces hold the activity of this run
echo "Calling the [$WEB_APP_NAME] web app [$WEB_APP_CALLS] times..."
for CALL in $(seq 1 "$WEB_APP_CALLS"); do
	STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "https://$WEB_APP_HOST_NAME/")
	echo "Call $CALL of $WEB_APP_CALLS to the [$WEB_APP_NAME] web app answered with status code [$STATUS_CODE]"
done

# The requests the web app served (AppRequests)
query_workspace \
	"Latest requests served by the [$WEB_APP_NAME] web app (AppRequests)" \
	"AppRequests | project TimeGenerated, Name, ResultCode, DurationMs, Success | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Name:Name,Result:ResultCode,DurationMs:DurationMs,Success:Success}"

# The web app's calls to Blob Storage (AppDependencies)
query_workspace \
	"Latest dependencies of the [$WEB_APP_NAME] web app (AppDependencies)" \
	"AppDependencies | project TimeGenerated, Name, Target, ResultCode, Success | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Name:Name,Target:Target,Result:ResultCode,Success:Success}"

# The application's own log records (AppTraces)
query_workspace \
	"Latest log records of the [$WEB_APP_NAME] web app (AppTraces)" \
	"AppTraces | project TimeGenerated, Message, SeverityLevel | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Message:Message,Severity:SeverityLevel}"

exit $EXIT_CODE
