#!/bin/bash

# Usage: query-telemetry.sh
#
# Waits for the web app to answer, shortens a link, follows it, and waits until the workers scanned it and rendered
# its QR code, then reads back what the web app and the function app sent through the connection string of the
# Application Insights resource to its Log Analytics workspace: the requests they served and the invocations of the
# functions (AppRequests), their calls to Table Storage, Key Vault, Service Bus, Queue and Blob Storage and PostgreSQL
# (AppDependencies), their log records (AppTraces), the LinkCreated, LinkFollowed and LinkScanned custom events
# (AppEvents), the custom metrics that count them (AppMetrics), and the exceptions they logged, if any (AppExceptions).
# Each record names the app that sent it in AppRoleName.
#
# The records reach the workspace within seconds on the emulator. On Azure they take minutes, so the wait and every
# query are retried: raise RETRY_COUNT there.

# Variables (the same defaults and environment overrides as deploy.sh)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
WEB_APP_NAME="${PREFIX}-urlshort-webapp-${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-urlshort-log-analytics-${SUFFIX}"
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
	STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "http://$WEB_APP_HOST_NAME/")

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

# Shorten a link: the web app stores it, sends a LinkCreated custom event, and hands it to the workers through Service
# Bus (abuse scan) and a storage queue (QR code)
echo "Shortening a link with the [$WEB_APP_NAME] web app..."
CODE=$(curl --max-time 30 --silent --request POST \
	--header "Content-Type: application/json" \
	--data '{"url": "https://learn.microsoft.com/azure/azure-monitor/app/app-insights-overview"}' \
	"http://$WEB_APP_HOST_NAME/shorten" | jq -r '.code // empty')

if [[ -n $CODE ]]; then
	echo "The [$WEB_APP_NAME] web app shortened the link to the [$CODE] code"
else
	echo "ERROR: the [$WEB_APP_NAME] web app shortened no link"
	exit 1
fi

# Follow the short link: the web app redirects, logs the click in PostgreSQL and sends a LinkFollowed custom event
STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "http://$WEB_APP_HOST_NAME/l/$CODE")
if [[ $STATUS_CODE == 302 ]]; then
	echo "The [$CODE] short link redirected with status code [$STATUS_CODE]"
else
	echo "ERROR: the [$CODE] short link answered with status code [$STATUS_CODE]"
	EXIT_CODE=1
fi

# Wait until the workers processed the link: the AbuseScan function records its verdict (and sends a LinkScanned
# custom event), the QrGenerator function has the QR code rendered
echo "Waiting for the workers to scan the [$CODE] link and render its QR code..."
ATTEMPT=1
while [ $ATTEMPT -le $RETRY_COUNT ]; do
	LINK=$(curl --max-time 30 --silent "http://$WEB_APP_HOST_NAME/api/links/$CODE")
	SCAN=$(echo "$LINK" | jq -r '.scan // empty' 2>/dev/null)
	QR=$(echo "$LINK" | jq -r '.qr // empty' 2>/dev/null)

	if [[ -n $SCAN && $SCAN != "pending" && $QR == "done" ]]; then
		echo "The workers scanned the [$CODE] link ([$SCAN]) and rendered its QR code"
		break
	fi

	if [ $ATTEMPT -lt $RETRY_COUNT ]; then
		echo "Attempt $ATTEMPT of $RETRY_COUNT: scan [$SCAN], QR code [$QR]. Waiting [$SLEEP] seconds before retry..."
		sleep $SLEEP
	fi
	ATTEMPT=$((ATTEMPT + 1))
done

if [[ -z $SCAN || $SCAN == "pending" || $QR != "done" ]]; then
	echo "ERROR: the workers did not process the [$CODE] link after $RETRY_COUNT attempts"
	EXIT_CODE=1
fi

# The requests the web app served and the invocations of the functions, counted per app and name (AppRequests)
query_workspace \
	"Requests and invocations per app (AppRequests)" \
	"AppRequests | summarize Requests = count(), Failed = countif(Success == false) by AppRoleName, Name | order by AppRoleName asc, Name asc" \
	"[].{App:AppRoleName,Name:Name,Requests:Requests,Failed:Failed}"

# The calls of the two apps to Table Storage, Key Vault, Service Bus, Queue and Blob Storage, PostgreSQL and each other,
# counted per app, type and target (AppDependencies)
query_workspace \
	"Dependencies per app, type and target (AppDependencies)" \
	"AppDependencies | summarize Calls = count(), Failed = countif(Success == false) by AppRoleName, DependencyType, Target | order by AppRoleName asc, Calls desc | take 20" \
	"[].{App:AppRoleName,Type:DependencyType,Target:Target,Calls:Calls,Failed:Failed}"

# The log records of the two apps (AppTraces)
query_workspace \
	"Latest log records of the two apps (AppTraces)" \
	"AppTraces | project TimeGenerated, AppRoleName, Message, SeverityLevel | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,App:AppRoleName,Message:Message,Severity:SeverityLevel}"

# The custom events of the link, counted per name: LinkCreated and LinkFollowed from the web app, LinkScanned from the
# function app (AppEvents)
query_workspace \
	"Custom events of the links (AppEvents)" \
	"AppEvents | where Name in ('LinkCreated', 'LinkFollowed', 'LinkScanned') | summarize Events = count() by AppRoleName, Name | order by Name asc" \
	"[].{App:AppRoleName,Event:Name,Events:Events}" \
	3

# The trace that confirms the link shortened above (AppTraces)
query_workspace \
	"Confirmation trace of the [$CODE] link (AppTraces)" \
	"AppTraces | where Message startswith 'Link created: $CODE ' | project TimeGenerated, Message, SeverityLevel | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Message:Message,Severity:SeverityLevel}"

# The custom metrics, exported once a minute: the links created and followed by the web app, and the links the abuse
# scan checked by verdict (AppMetrics)
query_workspace \
	"Custom metrics of the links (AppMetrics)" \
	"AppMetrics | where Name in ('links', 'link_scans') | summarize Total = sum(Sum) by Name, Dimension = coalesce(tostring(Properties['operation']), tostring(Properties['verdict'])) | order by Name asc, Dimension asc" \
	"[].{Metric:Name,Dimension:Dimension,Total:Total}" \
	3

# The exceptions the two apps logged with their stack trace (AppExceptions): a click that PostgreSQL fails to record
# produces one
show_workspace_records \
	"Latest exceptions of the two apps (AppExceptions)" \
	"AppExceptions | project TimeGenerated, ExceptionType, OuterMessage | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Exception:ExceptionType,Message:OuterMessage}" \
	"No exceptions: the two apps logged none."

exit $EXIT_CODE
