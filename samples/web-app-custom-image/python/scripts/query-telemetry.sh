#!/bin/bash

# Usage: query-telemetry.sh
#
# Waits for the web app to answer, calls its home page and its status endpoint, then reads back what the Microsoft
# OpenTelemetry Distro sent through the connection string of the Application Insights resource to its Log Analytics
# workspace: the requests the web app served (AppRequests), the application's own log records (AppTraces), the
# StatusRequested custom event of each status request (AppEvents), the custom metric that counts them (AppMetrics), and
# the exceptions of the requests that failed, if any (AppExceptions).
#
# The records reach the workspace within seconds on the emulator. On Azure they take minutes, so the wait and every
# query are retried, for up to fifteen minutes each by default there (RETRY_COUNT).

# Variables (the same defaults and environment overrides as deploy.sh)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
WEB_APP_CALLS="${WEB_APP_CALLS:-5}"
# On Azure a custom metric took more than five minutes to reach the workspace (2026-11-26): the OpenTelemetry Distro
# exports metrics once a minute. The default wait there is fifteen minutes per query.
if [[ $(az cloud show --query name --output tsv | tr -d '\r') == "LocalStack" ]]; then
	RETRY_COUNT="${RETRY_COUNT:-30}"
else
	RETRY_COUNT="${RETRY_COUNT:-90}"
fi
SLEEP="${SLEEP:-10}"
EXIT_CODE=0

# Call the home page and the status endpoint once, quietly. Every wait for records calls the web app again: on Azure,
# App Service applies the APPLICATIONINSIGHTS_CONNECTION_STRING app setting that deploy.sh sets last by starting a new
# container about a minute after the deployment ends, and the calls an earlier container served may never reach the
# workspace
call_web_app_once() {
	curl --max-time 30 --silent --output /dev/null "https://$WEB_APP_HOST_NAME/"
	curl --max-time 30 --silent --output /dev/null "https://$WEB_APP_HOST_NAME/api/status"
}

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
				echo "Attempt $attempt of $RETRY_COUNT: [${records:-0}] of the [$minimum_records] records expected so far. Calling the web app again and waiting [$SLEEP] seconds before retry..."
				call_web_app_once
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

# Call the home page and the status endpoint, so that AppRequests and AppTraces hold the calls of this run, AppEvents
# their StatusRequested custom events and AppMetrics the status_requests custom metric
echo "Calling the home page and the status endpoint of the [$WEB_APP_NAME] web app [$WEB_APP_CALLS] times each..."
for CALL in $(seq 1 "$WEB_APP_CALLS"); do
	HOME_STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "https://$WEB_APP_HOST_NAME/")
	STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "https://$WEB_APP_HOST_NAME/api/status")
	echo "Call $CALL of $WEB_APP_CALLS: the home page answered [$HOME_STATUS_CODE], the status endpoint [$STATUS_CODE]"
	if [[ $STATUS_CODE != 200 ]]; then
		echo "ERROR: the status endpoint of the [$WEB_APP_NAME] web app answered with status code [$STATUS_CODE]"
		EXIT_CODE=1
	fi
done

# The requests the web app served (AppRequests)
query_workspace \
	"Latest requests served by the [$WEB_APP_NAME] web app (AppRequests)" \
	"AppRequests | project TimeGenerated, Name, ResultCode, DurationMs, Success | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Name:Name,Result:ResultCode,DurationMs:DurationMs,Success:Success}"

# The application's own log records (AppTraces)
query_workspace \
	"Latest log records of the [$WEB_APP_NAME] web app (AppTraces)" \
	"AppTraces | project TimeGenerated, Message, SeverityLevel | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Message:Message,Severity:SeverityLevel}"

# The StatusRequested custom events of the status requests, with the image the app runs (AppEvents)
query_workspace \
	"Latest StatusRequested custom events of the [$WEB_APP_NAME] web app (AppEvents)" \
	"AppEvents | where Name == 'StatusRequested' | project TimeGenerated, Name, Image = tostring(Properties['image.name']) | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Name:Name,Image:Image}"

# The traces that confirm the status requests the web app answered (AppTraces)
query_workspace \
	"Confirmation traces of the status requests (AppTraces)" \
	"AppTraces | where Message startswith 'Status returned: ' | project TimeGenerated, Message, SeverityLevel | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Message:Message,Severity:SeverityLevel}"

# The custom metric that counts the status requests by image, exported once a minute (AppMetrics)
query_workspace \
	"Custom metric of the status requests (AppMetrics)" \
	"AppMetrics | where Name == 'status_requests' | summarize Total = sum(Sum) by Name, Image = tostring(Properties['image'])" \
	"[].{Metric:Name,Image:Image,Total:Total}"

# The exceptions of the requests that failed, with their stack trace (AppExceptions)
show_workspace_records \
	"Latest exceptions of the [$WEB_APP_NAME] web app (AppExceptions)" \
	"AppExceptions | project TimeGenerated, ExceptionType, OuterMessage | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Exception:ExceptionType,Message:OuterMessage}" \
	"No exceptions: no request of the [$WEB_APP_NAME] web app failed."

exit $EXIT_CODE
