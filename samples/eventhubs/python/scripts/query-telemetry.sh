#!/bin/bash

# Usage: query-telemetry.sh
#
# Calls the operations dashboard, then reads back what the fraud detection function and the dashboard sent through the
# connection string of the Application Insights resource to its Log Analytics workspace: the invocations of the
# FraudDetector function and the requests the dashboard served (AppRequests), the calls they made to Event Hubs, Blob
# Storage and, when the dashboard has a token for it, the Schema Registry (AppDependencies), their log records
# (AppTraces), the FraudDetected custom event of each alert (AppEvents), the custom metric that counts the payments the
# function screened (AppMetrics), and the exceptions they logged, if any (AppExceptions). Each record names the app
# that sent it in AppRoleName. Run it after run-pipeline.sh, which sends the payments the function screens.
#
# The records reach the workspace within seconds on the emulator. On Azure they take minutes, so every query is
# retried, for up to fifteen minutes each by default there (RETRY_COUNT).

# Variables (the same defaults and environment overrides as the deploy scripts)
PREFIX="${PREFIX:-local}"
RESOURCE_GROUP_NAME="${PREFIX}-eventhubs-rg"
LOG_ANALYTICS_NAME="${PREFIX}-eh-logs"
WEB_APP_NAME="${PREFIX}-eh-dashboard"
DASHBOARD_CALLS="${DASHBOARD_CALLS:-3}"
# On Azure a custom metric took more than five minutes to reach the workspace (2026-11-26): the OpenTelemetry Distro
# exports metrics once a minute. The default wait there is fifteen minutes per query.
if [[ $(az cloud show --query name --output tsv | tr -d '\r') == "LocalStack" ]]; then
	RETRY_COUNT="${RETRY_COUNT:-30}"
else
	RETRY_COUNT="${RETRY_COUNT:-90}"
fi
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

# Get the default host name of the dashboard
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

# Wait until the dashboard answers: the deployment builds it asynchronously, and only a running app sends telemetry
echo "Waiting for the [$WEB_APP_NAME] web app to answer..."
ATTEMPT=1
while [ $ATTEMPT -le $RETRY_COUNT ]; do
	STATUS_CODE=$(curl --max-time 30 --silent --output /dev/null --write-out "%{http_code}" "https://$WEB_APP_HOST_NAME/health")

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

# Ask the dashboard for its overview, so that AppRequests, AppDependencies and AppTraces hold its activity of this run.
# Each call reads the partitions, the checkpoints, the alerts, the Capture archives and the Schema Registry.
echo "Calling the overview of the [$WEB_APP_NAME] web app [$DASHBOARD_CALLS] times..."
for CALL in $(seq 1 "$DASHBOARD_CALLS"); do
	STATUS_CODE=$(curl --max-time 60 --silent --output /dev/null --write-out "%{http_code}" "https://$WEB_APP_HOST_NAME/api/overview")
	echo "Call $CALL of $DASHBOARD_CALLS to the overview of the [$WEB_APP_NAME] web app answered with status code [$STATUS_CODE]"
	if [[ $STATUS_CODE != 200 ]]; then
		EXIT_CODE=1
	fi
done

# The invocations of the FraudDetector function, one per batch of payments, and the requests the dashboard served,
# counted per app and name (AppRequests)
query_workspace \
	"Invocations and requests per app (AppRequests)" \
	"AppRequests | summarize Requests = count(), Failed = countif(Success == false) by AppRoleName, Name | order by AppRoleName asc, Name asc" \
	"[].{App:AppRoleName,Name:Name,Requests:Requests,Failed:Failed}" \
	2

# The calls of the two apps to Event Hubs, Blob Storage and the Schema Registry, counted per app, type and target
# (AppDependencies)
query_workspace \
	"Dependencies per app, type and target (AppDependencies)" \
	"AppDependencies | summarize Calls = count(), Failed = countif(Success == false) by AppRoleName, DependencyType, Target | order by AppRoleName asc, Calls desc | take 20" \
	"[].{App:AppRoleName,Type:DependencyType,Target:Target,Calls:Calls,Failed:Failed}"

# The log records of the two apps, such as FRAUD_ALERT, FRAUD_BATCH and OVERVIEW (AppTraces)
query_workspace \
	"Latest log records of the two apps (AppTraces)" \
	"AppTraces | project TimeGenerated, AppRoleName, Message, SeverityLevel | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,App:AppRoleName,Message:Message,Severity:SeverityLevel}"

# The FraudDetected custom events, counted per channel of the payment (AppEvents)
query_workspace \
	"FraudDetected custom events, per channel (AppEvents)" \
	"AppEvents | where Name == 'FraudDetected' | summarize Events = count(), Amount = round(sum(todouble(Properties['payment.amount'])), 2) by Channel = tostring(Properties['payment.channel']) | order by Channel asc" \
	"[].{Channel:Channel,Events:Events,Amount:Amount}"

# The traces that confirm the payment batches the function screened (AppTraces)
query_workspace \
	"Confirmation traces of the payment batches screened (AppTraces)" \
	"AppTraces | where Message startswith 'FRAUD_BATCH ' | project TimeGenerated, Message, SeverityLevel | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Message:Message,Severity:SeverityLevel}"

# The custom metric that counts the payments the function screened, by outcome (legitimate, flagged), exported once a
# minute (AppMetrics): run-pipeline.sh sends both kinds
query_workspace \
	"Custom metric of the payments screened (AppMetrics)" \
	"AppMetrics | where Name == 'payments_screened' | summarize Total = sum(Sum) by Name, Outcome = tostring(Properties['outcome']) | order by Outcome asc" \
	"[].{Metric:Name,Outcome:Outcome,Total:Total}" \
	2

# The exceptions the two apps logged with their stack trace (AppExceptions)
show_workspace_records \
	"Latest exceptions of the two apps (AppExceptions)" \
	"AppExceptions | project TimeGenerated, ExceptionType, OuterMessage | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Exception:ExceptionType,Message:OuterMessage}" \
	"No exceptions: the two apps logged none."

exit $EXIT_CODE
