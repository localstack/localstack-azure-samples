#!/bin/bash

# Usage: query-telemetry.sh
#
# Runs test.sh, which uploads a text file that the function processes, then reads back what the Functions host and the
# .NET worker sent through the connection string of the Application Insights resource to its Log Analytics workspace:
# the invocations of the function (AppRequests), the log records of the function and of the host (AppTraces), the
# BlobProcessed custom event of each processed file (AppEvents), the custom metric that counts them (AppMetrics), and
# the exceptions the function logged, if any (AppExceptions).
#
# The records reach the workspace within seconds on the emulator. On Azure they take minutes, so every query is
# retried, for up to fifteen minutes each by default there (RETRY_COUNT).

# Variables (the same defaults and environment overrides as the deploy scripts)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
FUNCTION_APP_NAME="${PREFIX}-functionapp-${SUFFIX}"
FUNCTION_NAME="ProcessTextFunction"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
INPUT_CONTAINER_NAME="input"
# On Azure a custom metric took more than five minutes to reach the workspace (2026-11-26): the OpenTelemetry Distro
# exports metrics once a minute. The default wait there is fifteen minutes per query.
if [[ $(az cloud show --query name --output tsv | tr -d '\r') == "LocalStack" ]]; then
	RETRY_COUNT="${RETRY_COUNT:-30}"
else
	RETRY_COUNT="${RETRY_COUNT:-90}"
fi
SLEEP="${SLEEP:-10}"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXIT_CODE=0

# Run a KQL query on the Log Analytics workspace and print the records it returns as a table, retrying while the
# records are still on their way to the workspace
# $1: what the query reads
# $2: the KQL query
# $3: the JMESPath projection that names and orders the columns of the table
# $4: the number of records the query must return (1 when not given)
# $5: a command that produces new records, run once a minute when the records are three minutes late (none when not
#     given): the apps export their custom metrics once a minute, and on Azure the restart that follows a deployment
#     can stop an app before it exported the points of the calls this script made
query_workspace() {
	local description=$1
	local query=$2
	local columns=$3
	local minimum_records=${4:-1}
	local produce_again=${5:-}
	local records
	local attempt=1
	local started=$SECONDS
	local last_produced=$SECONDS

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
				if [[ -n $produce_again ]] && ((SECONDS - started >= 180 && SECONDS - last_produced >= 60)); then
					$produce_again
					last_produced=$SECONDS
				fi
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

# Invoke the function: test.sh uploads a text file to the input container and waits for the processed one
echo "Invoking the [$FUNCTION_NAME] function of the [$FUNCTION_APP_NAME] function app with test.sh..."
bash "$CURRENT_DIR/test.sh"

if [[ $? == 0 ]]; then
	echo "The [$FUNCTION_NAME] function processed the uploaded file"
else
	echo "ERROR: test.sh failed, so the [$FUNCTION_NAME] function did not run"
	exit 1
fi

# Upload another copy of test.sh's text file to the input container, so that the custom metric gets a new point: the
# function app exports its metrics once a minute, and on Azure the Functions host can restart right after the first
# invocation that follows a deployment, before it exported the point of the file test.sh uploaded
upload_another_file() {
	local blob_name
	blob_name="input-$(date +%Y-%m-%d-%H-%M-%S).txt"
	if (cd "$CURRENT_DIR" && az storage blob upload \
		--container-name "$INPUT_CONTAINER_NAME" \
		--file input.txt \
		--name "$blob_name" \
		--account-name "$STORAGE_ACCOUNT_NAME" \
		--auth-mode login \
		--only-show-errors 1>/dev/null); then
		echo "Uploaded the [$blob_name] file to the [$INPUT_CONTAINER_NAME] container, so that the custom metric gets a new point"
	else
		echo "Failed to upload the [$blob_name] file to the [$INPUT_CONTAINER_NAME] container"
	fi
}

# The invocations of the function (AppRequests)
query_workspace \
	"Latest invocations of the [$FUNCTION_NAME] function (AppRequests)" \
	"AppRequests | where Name == '$FUNCTION_NAME' | project TimeGenerated, Name, Success, ResultCode, DurationMs | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Name:Name,Success:Success,Result:ResultCode,DurationMs:DurationMs}"

# The log records of the function and of the Functions host (AppTraces)
query_workspace \
	"Latest log records of the [$FUNCTION_APP_NAME] function app (AppTraces)" \
	"AppTraces | project TimeGenerated, Message, SeverityLevel | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Message:Message,Severity:SeverityLevel}"

# The custom event of each file the function processed, with the name and the size of the blob (AppEvents)
query_workspace \
	"Latest BlobProcessed custom events of the [$FUNCTION_NAME] function (AppEvents)" \
	"AppEvents | where Name == 'BlobProcessed' | project TimeGenerated, Name, Blob = tostring(Properties['blob.name']), Size = tostring(Properties['blob.size']) | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Name:Name,Blob:Blob,Size:Size}"

# The traces that confirm the blobs the function processed, including the one above (AppTraces)
query_workspace \
	"Confirmation traces of the processed blobs (AppTraces)" \
	"AppTraces | where Message startswith 'Blob processed: ' | project TimeGenerated, Message, SeverityLevel | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Message:Message,Severity:SeverityLevel}"

# The custom metric that counts the processed files, exported once a minute (AppMetrics). When it is three minutes
# late, the script uploads another file once a minute.
query_workspace \
	"Custom metric of the processed files (AppMetrics)" \
	"AppMetrics | where Name == 'processed_blobs' | summarize Total = sum(Sum) by Name, Container = tostring(Properties['container'])" \
	"[].{Metric:Name,Container:Container,Total:Total}" \
	1 \
	upload_another_file

# The exceptions the function logged with their stack trace (AppExceptions): a file that isn't UTF-8 text, for example,
# produces one
show_workspace_records \
	"Latest exceptions of the [$FUNCTION_APP_NAME] function app (AppExceptions)" \
	"AppExceptions | project TimeGenerated, ExceptionType, OuterMessage | order by TimeGenerated desc | take 10" \
	"[].{Time:TimeGenerated,Exception:ExceptionType,Message:OuterMessage}" \
	"No exceptions: the [$FUNCTION_APP_NAME] function app logged none."

exit $EXIT_CODE
