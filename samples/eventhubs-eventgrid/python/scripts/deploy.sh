#!/bin/bash

# =============================================================================
# Cold-path automation: Event Hubs Capture -> Event Grid -> Event Hubs -> Functions
#
# Deploys the whole chain:
#   telemetry hub (Capture -> Avro in Blob)
#     -> Microsoft.EventHub.CaptureFileCreated raised to an Event Grid system topic
#     -> subscription with an EventHub destination -> capture-notifications hub
#     -> Function App (Event Hubs trigger) decodes the archive and aggregates it
#     -> curated hub (Event Hubs output binding)
#
# Everything runs against the LocalStack Azure emulator. Run 'lstk az start-interception' first.
# =============================================================================

PREFIX="${PREFIX:-local}"
SUFFIX='telemetry'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-ehgrid-rg"
EVENTHUB_NAMESPACE_NAME="${PREFIX}-ehns-${SUFFIX}"

TELEMETRY_HUB_NAME='telemetry'
NOTIFICATION_HUB_NAME='capture-notifications'
CURATED_HUB_NAME='curated'
TELEMETRY_PARTITION_COUNT=4
NOTIFICATION_PARTITION_COUNT=2
CURATED_PARTITION_COUNT=2
RETENTION_HOURS=24

# Capture flushes on whichever comes first. 60s is the minimum Azure allows, and it sets the
# tempo of the whole demo: nothing downstream happens until a window closes.
CAPTURE_INTERVAL_SECONDS=60
CAPTURE_SIZE_LIMIT_BYTES=10485760
CAPTURE_CONTAINER_NAME='telemetry-archive'

STORAGE_ACCOUNT_NAME="${PREFIX}ehgrid${SUFFIX:0:4}"
SYSTEM_TOPIC_NAME="${PREFIX}-ehns-systopic"
SUBSCRIPTION_NAME='capture-to-eventhub'
# Azure's topic type for an Event Hubs namespace as an event source.
EVENTHUB_TOPIC_TYPE='Microsoft.Eventhub.Namespaces'

FUNCTION_APP_NAME="${PREFIX}-ehgrid-processor"
APP_SERVICE_PLAN_NAME="${PREFIX}-ehgrid-plan"
CAPTURE_CONSUMER_GROUP='capture-processor'
TEMPERATURE_LIMIT=80
LOG_ANALYTICS_NAME="${PREFIX}-ehgrid-log-analytics"
APPLICATION_INSIGHTS_NAME="${PREFIX}-ehgrid-insights"
DIAGNOSTIC_SETTINGS_NAME='default'

SEND_RULE_NAME='telemetry-send'
LISTEN_RULE_NAME='pipeline-listen'

FUNCTION_ZIP='capture_processor.zip'
DEPLOY_RETRY_COUNT=10
DEPLOY_RETRY_SLEEP=60

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$CURRENT_DIR/../src" && pwd)"
# On Windows, Git Bash and MSYS2 shells pass a path such as /tmp/... unconverted to Windows programs
# (az, curl, jq, python, docker) when MSYS_NO_PATHCONV=1 is set, as the README asks. cygpath, which
# those shells provide, returns the C:/... form those programs can open; elsewhere the path is unchanged.
native_path() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -m "$1"
	else
		echo "$1"
	fi
}

cd "$CURRENT_DIR" || exit 1

fail() {
	echo "ERROR: $1"
	exit 1
}

step() {
	echo ""
	echo "=== $1 ==="
}

# -----------------------------------------------------------------------------
step "[1/11] Resource group"
# -----------------------------------------------------------------------------
az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" \
	--only-show-errors 1>/dev/null || fail "could not create the resource group"
echo "Resource group [$RESOURCE_GROUP_NAME] ready."

# -----------------------------------------------------------------------------
step "[2/11] Log Analytics workspace and Application Insights"
# -----------------------------------------------------------------------------
if ! az monitor log-analytics workspace show --workspace-name "$LOG_ANALYTICS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az monitor log-analytics workspace create \
		--workspace-name "$LOG_ANALYTICS_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null || fail "could not create the Log Analytics workspace"
	echo "Created Log Analytics workspace [$LOG_ANALYTICS_NAME]."
else
	echo "Log Analytics workspace [$LOG_ANALYTICS_NAME] already exists."
fi
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show --workspace-name "$LOG_ANALYTICS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query id -o tsv --only-show-errors)
[[ -n "$LOG_ANALYTICS_ID" ]] || fail "could not read the Log Analytics workspace id"

# A workspace-based Application Insights resource: the function app's telemetry lands in the workspace
if ! az monitor app-insights component show --app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az monitor app-insights component create \
		--app "$APPLICATION_INSIGHTS_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--application-type web \
		--workspace "$LOG_ANALYTICS_ID" \
		--only-show-errors 1>/dev/null || fail "could not create the Application Insights resource"
	echo "Created Application Insights resource [$APPLICATION_INSIGHTS_NAME]."
else
	echo "Application Insights resource [$APPLICATION_INSIGHTS_NAME] already exists."
fi
APPLICATION_INSIGHTS_CONNECTION_STRING=$(az monitor app-insights component show --app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query connectionString -o tsv --only-show-errors)
[[ -n "$APPLICATION_INSIGHTS_CONNECTION_STRING" ]] || fail "could not read the Application Insights connection string"

# -----------------------------------------------------------------------------
step "[3/11] Storage account for Capture archives"
# -----------------------------------------------------------------------------
if ! az storage account show --name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az storage account create \
		--name "$STORAGE_ACCOUNT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--sku Standard_LRS \
		--kind StorageV2 \
		--only-show-errors 1>/dev/null || fail "could not create storage account"
	echo "Created storage account [$STORAGE_ACCOUNT_NAME]."
else
	echo "Storage account [$STORAGE_ACCOUNT_NAME] already exists."
fi

STORAGE_KEY=$(az storage account keys list --account-name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query "[0].value" -o tsv --only-show-errors)
STORAGE_BLOB=$(az storage account show -n "$STORAGE_ACCOUNT_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query primaryEndpoints.blob -o tsv --only-show-errors)
STORAGE_QUEUE=$(az storage account show -n "$STORAGE_ACCOUNT_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query primaryEndpoints.queue -o tsv --only-show-errors)
STORAGE_TABLE=$(az storage account show -n "$STORAGE_ACCOUNT_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query primaryEndpoints.table -o tsv --only-show-errors)
[[ -n "$STORAGE_KEY" ]] || fail "could not read the storage account key"

# Explicit endpoints rather than EndpointSuffix: the Functions host cannot parse a suffix that
# carries a port, which it does against the emulator.
STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_KEY};BlobEndpoint=${STORAGE_BLOB};QueueEndpoint=${STORAGE_QUEUE};TableEndpoint=${STORAGE_TABLE}"

az storage container create --name "$CAPTURE_CONTAINER_NAME" \
	--connection-string "$STORAGE_CONNECTION_STRING" --only-show-errors 1>/dev/null ||
	fail "could not create the capture container"
echo "Blob container [$CAPTURE_CONTAINER_NAME] ready for Capture archives."

# -----------------------------------------------------------------------------
step "[4/11] Event Hubs namespace (Standard tier - Capture needs it)"
# -----------------------------------------------------------------------------
if ! az eventhubs namespace show --name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az eventhubs namespace create \
		--name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--sku Standard \
		--only-show-errors 1>/dev/null || fail "could not create the Event Hubs namespace"
	echo "Created Event Hubs namespace [$EVENTHUB_NAMESPACE_NAME]."
else
	echo "Event Hubs namespace [$EVENTHUB_NAMESPACE_NAME] already exists."
fi

NAMESPACE_ID=$(az eventhubs namespace show --name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query id -o tsv --only-show-errors)
STORAGE_ACCOUNT_ID=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query id -o tsv --only-show-errors)

# -----------------------------------------------------------------------------
step "[5/11] Three hubs: telemetry (with Capture), notifications, curated"
# -----------------------------------------------------------------------------
if ! az eventhubs eventhub show --name "$TELEMETRY_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null; then
	az eventhubs eventhub create \
		--name "$TELEMETRY_HUB_NAME" \
		--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--partition-count "$TELEMETRY_PARTITION_COUNT" \
		--retention-time-in-hours "$RETENTION_HOURS" \
		--cleanup-policy Delete \
		--enable-capture true \
		--capture-interval "$CAPTURE_INTERVAL_SECONDS" \
		--capture-size-limit "$CAPTURE_SIZE_LIMIT_BYTES" \
		--skip-empty-archives true \
		--destination-name EventHubArchive.AzureBlockBlob \
		--storage-account "$STORAGE_ACCOUNT_ID" \
		--blob-container "$CAPTURE_CONTAINER_NAME" \
		--archive-name-format '{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}' \
		--only-show-errors 1>/dev/null || fail "could not create hub [$TELEMETRY_HUB_NAME]"
	echo "Created [$TELEMETRY_HUB_NAME] with $TELEMETRY_PARTITION_COUNT partitions and Capture enabled."
else
	echo "Event hub [$TELEMETRY_HUB_NAME] already exists."
fi

for hub_spec in "$NOTIFICATION_HUB_NAME:$NOTIFICATION_PARTITION_COUNT" "$CURATED_HUB_NAME:$CURATED_PARTITION_COUNT"; do
	hub_name="${hub_spec%%:*}"
	partitions="${hub_spec##*:}"
	if ! az eventhubs eventhub show --name "$hub_name" \
		--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
		--only-show-errors &>/dev/null; then
		az eventhubs eventhub create \
			--name "$hub_name" \
			--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--partition-count "$partitions" \
			--retention-time-in-hours "$RETENTION_HOURS" \
			--cleanup-policy Delete \
			--only-show-errors 1>/dev/null || fail "could not create hub [$hub_name]"
		echo "Created [$hub_name] with $partitions partitions."
	else
		echo "Event hub [$hub_name] already exists."
	fi
done

# -----------------------------------------------------------------------------
step "[6/11] Consumer group for the processor"
# -----------------------------------------------------------------------------
if ! az eventhubs eventhub consumer-group show \
	--consumer-group-name "$CAPTURE_CONSUMER_GROUP" --eventhub-name "$NOTIFICATION_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null; then
	az eventhubs eventhub consumer-group create \
		--consumer-group-name "$CAPTURE_CONSUMER_GROUP" \
		--eventhub-name "$NOTIFICATION_HUB_NAME" \
		--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--only-show-errors 1>/dev/null || fail "could not create consumer group"
	echo "Created consumer group [$CAPTURE_CONSUMER_GROUP] on [$NOTIFICATION_HUB_NAME]."
else
	echo "Consumer group [$CAPTURE_CONSUMER_GROUP] already exists."
fi

# -----------------------------------------------------------------------------
step "[7/11] Least-privilege authorization rules"
# -----------------------------------------------------------------------------
# Producers may only Send to the telemetry hub.
if ! az eventhubs eventhub authorization-rule show --name "$SEND_RULE_NAME" \
	--eventhub-name "$TELEMETRY_HUB_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az eventhubs eventhub authorization-rule create \
		--name "$SEND_RULE_NAME" --eventhub-name "$TELEMETRY_HUB_NAME" \
		--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
		--rights Send --only-show-errors 1>/dev/null || fail "could not create rule [$SEND_RULE_NAME]"
	echo "Created send-only rule [$SEND_RULE_NAME] on [$TELEMETRY_HUB_NAME]."
fi

# The demo scripts read every hub, so this one is namespace-wide - but Listen only.
if ! az eventhubs namespace authorization-rule show --name "$LISTEN_RULE_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null; then
	az eventhubs namespace authorization-rule create \
		--name "$LISTEN_RULE_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" --rights Listen \
		--only-show-errors 1>/dev/null || fail "could not create rule [$LISTEN_RULE_NAME]"
	echo "Created namespace-wide listen-only rule [$LISTEN_RULE_NAME]."
fi

SEND_CONNECTION=$(az eventhubs eventhub authorization-rule keys list --name "$SEND_RULE_NAME" \
	--eventhub-name "$TELEMETRY_HUB_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query primaryConnectionString -o tsv --only-show-errors)
LISTEN_CONNECTION=$(az eventhubs namespace authorization-rule keys list --name "$LISTEN_RULE_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryConnectionString -o tsv --only-show-errors)
NAMESPACE_CONNECTION=$(az eventhubs namespace authorization-rule keys list \
	--name RootManageSharedAccessKey --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query primaryConnectionString -o tsv --only-show-errors)

[[ -n "$SEND_CONNECTION" ]] || fail "could not read the send connection string"
[[ -n "$LISTEN_CONNECTION" ]] || fail "could not read the listen connection string"
[[ -n "$NAMESPACE_CONNECTION" ]] || fail "could not read the namespace connection string"

# -----------------------------------------------------------------------------
step "[8/11] Event Grid system topic on the namespace"
# -----------------------------------------------------------------------------
# A system topic is how a subscriber reaches the events an Azure resource raises about itself.
# Its source is the namespace, and Event Hubs raises Microsoft.EventHub.CaptureFileCreated to it.
if ! az eventgrid system-topic show --name "$SYSTEM_TOPIC_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az eventgrid system-topic create \
		--name "$SYSTEM_TOPIC_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--topic-type "$EVENTHUB_TOPIC_TYPE" \
		--source "$NAMESPACE_ID" \
		--only-show-errors 1>/dev/null || fail "could not create the system topic"
	echo "Created system topic [$SYSTEM_TOPIC_NAME] over [$EVENTHUB_NAMESPACE_NAME]."
else
	echo "System topic [$SYSTEM_TOPIC_NAME] already exists."
fi

NOTIFICATION_HUB_ID=$(az eventhubs eventhub show --name "$NOTIFICATION_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query id -o tsv --only-show-errors)
[[ -n "$NOTIFICATION_HUB_ID" ]] || fail "could not read the notification hub id"

# The subscription's destination is an event hub, so the notification becomes a stream the
# Functions host can trigger on - no webhook to expose, no polling.
if ! az eventgrid system-topic event-subscription show --name "$SUBSCRIPTION_NAME" \
	--system-topic-name "$SYSTEM_TOPIC_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null; then
	az eventgrid system-topic event-subscription create \
		--name "$SUBSCRIPTION_NAME" \
		--system-topic-name "$SYSTEM_TOPIC_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--endpoint-type eventhub \
		--endpoint "$NOTIFICATION_HUB_ID" \
		--only-show-errors 1>/dev/null || fail "could not create the event subscription"
	echo "Created subscription [$SUBSCRIPTION_NAME] -> event hub [$NOTIFICATION_HUB_NAME]."
else
	echo "Event subscription [$SUBSCRIPTION_NAME] already exists."
fi

# -----------------------------------------------------------------------------
step "[9/11] Function App (Event Hubs trigger -> archive processor)"
# -----------------------------------------------------------------------------
if ! az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null; then
	az functionapp create \
		--name "$FUNCTION_APP_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--storage-account "$STORAGE_ACCOUNT_NAME" \
		--consumption-plan-location "$LOCATION" \
		--runtime python \
		--runtime-version 3.12 \
		--functions-version 4 \
		--app-insights "$APPLICATION_INSIGHTS_NAME" \
		--os-type Linux \
		--only-show-errors 1>/dev/null || fail "could not create the function app"
	echo "Created function app [$FUNCTION_APP_NAME]."
else
	echo "Function app [$FUNCTION_APP_NAME] already exists."
fi

# The processor imports fastavro and azure-storage-blob to decode an archive, so the deployment
# has to run a build that installs requirements.txt. Without these two settings the package is
# copied as-is, the imports fail at invocation time, and the notification looks like it was never
# processed.
az functionapp config appsettings set \
	--name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--settings \
	"AzureWebJobsStorage=$STORAGE_CONNECTION_STRING" \
	"WEBSITE_CONTENTAZUREFILECONNECTIONSTRING=$STORAGE_CONNECTION_STRING" \
	"STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING" \
	"ENABLE_ORYX_BUILD=true" \
	"SCM_DO_BUILD_DURING_DEPLOYMENT=true" \
	"EVENTHUB_NOTIFICATION_CONNECTION=$NAMESPACE_CONNECTION" \
	"EVENTHUB_CURATED_CONNECTION=$NAMESPACE_CONNECTION" \
	"NOTIFICATION_HUB_NAME=$NOTIFICATION_HUB_NAME" \
	"CURATED_HUB_NAME=$CURATED_HUB_NAME" \
	"CAPTURE_CONSUMER_GROUP=$CAPTURE_CONSUMER_GROUP" \
	"TEMPERATURE_LIMIT=$TEMPERATURE_LIMIT" \
	"APPLICATIONINSIGHTS_CONNECTION_STRING=$APPLICATION_INSIGHTS_CONNECTION_STRING" \
	--only-show-errors 1>/dev/null || fail "could not set function app settings"
echo "Configured function app settings."

cd "$SRC_DIR/functions" || fail "missing src/functions"
rm -f "$CURRENT_DIR/$FUNCTION_ZIP"
zip -r "$(native_path "$CURRENT_DIR/$FUNCTION_ZIP")" function_app.py host.json requirements.txt 1>/dev/null
cd "$CURRENT_DIR" || exit 1

echo "Deploying the processor (the first run pulls the build image and can take a few minutes)..."
# The function app runs on a Linux Consumption plan, which has no companion deployment site: Azure answers
# az functionapp deploy with "This API isn't available in this environment yet!". Zip deployment with a remote build,
# which installs requirements.txt, deploys it (Learn, "Deployment technologies in Azure Functions"). On Azure the first
# deployment to a new function app can time out, and its deployment endpoint can answer 503 (Site Unavailable) for
# several minutes after the app is created, so a failed attempt is retried for about ten minutes
DEPLOYED=0
for ((ATTEMPT = 1; ATTEMPT <= DEPLOY_RETRY_COUNT; ATTEMPT++)); do
	az functionapp deployment source config-zip \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$FUNCTION_APP_NAME" \
		--src "$FUNCTION_ZIP" \
		--build-remote true 1>/dev/null

	if [[ $? == 0 ]]; then
		DEPLOYED=1
		break
	fi

	if [[ $ATTEMPT -lt $DEPLOY_RETRY_COUNT ]]; then
		echo "Attempt $ATTEMPT of $DEPLOY_RETRY_COUNT to deploy function app [$FUNCTION_APP_NAME] failed. Waiting [$DEPLOY_RETRY_SLEEP] seconds before retry..."
		sleep $DEPLOY_RETRY_SLEEP
	fi
done
[[ $DEPLOYED == 1 ]] || fail "could not deploy the function app"
rm -f "$FUNCTION_ZIP"
echo "Deployed the capture processor."

# -----------------------------------------------------------------------------
step "[10/11] Diagnostic settings"
# -----------------------------------------------------------------------------
# Create the diagnostic settings of a resource that sends its resource logs and its platform metrics to the workspace,
# unless they already exist
# $1: the resource id
# $2: the resource description
# $3...: the arguments of az monitor diagnostic-settings create that pick the logs and the metrics
diagnostic_settings() {
	local resource_id=$1
	local description=$2
	shift 2
	if az monitor diagnostic-settings show --name "$DIAGNOSTIC_SETTINGS_NAME" --resource "$resource_id" \
		--only-show-errors &>/dev/null; then
		echo "Diagnostic settings of the $description already exist."
		return
	fi
	az monitor diagnostic-settings create \
		--name "$DIAGNOSTIC_SETTINGS_NAME" \
		--resource "$resource_id" \
		--workspace "$LOG_ANALYTICS_ID" \
		"$@" \
		--only-show-errors 1>/dev/null || fail "could not create the diagnostic settings of the $description"
	echo "Created the diagnostic settings of the $description."
}

STORAGE_ACCOUNT_ID=$(az storage account show -n "$STORAGE_ACCOUNT_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query id -o tsv --only-show-errors)
FUNCTION_APP_ID=$(az functionapp show -n "$FUNCTION_APP_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query id -o tsv --only-show-errors)
# The Consumption plan az functionapp create made for the app, whose name Azure picks
FUNCTION_PLAN_ID=$(az functionapp show -n "$FUNCTION_APP_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query appServicePlanId -o tsv --only-show-errors)
SYSTEM_TOPIC_ID=$(az eventgrid system-topic show -n "$SYSTEM_TOPIC_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query id -o tsv --only-show-errors)
[[ -n "$STORAGE_ACCOUNT_ID" && -n "$FUNCTION_APP_ID" && -n "$FUNCTION_PLAN_ID" && -n "$SYSTEM_TOPIC_ID" ]] ||
	fail "could not read the resource ids"

# The storage account offers metrics only; its services send the logs of their requests and their metrics
diagnostic_settings "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account" \
	--metrics '[{"category": "Capacity", "enabled": true}, {"category": "Transaction", "enabled": true}]'
for SERVICE in blob queue table; do
	diagnostic_settings "$STORAGE_ACCOUNT_ID/${SERVICE}Services/default" "$SERVICE service of the [$STORAGE_ACCOUNT_NAME] storage account" \
		--logs '[{"category": "StorageRead", "enabled": true}, {"category": "StorageWrite", "enabled": true}, {"category": "StorageDelete", "enabled": true}]' \
		--metrics '[{"category": "Capacity", "enabled": true}, {"category": "Transaction", "enabled": true}]'
done

# The namespace writes its operational logs to the resource-specific AZMSOperationalLogs table; its other categories
# have AzureDiagnostics only. ArchiveLogs records the Capture archives; the runtime audit logs are left out, since
# Event Hubs writes them only in the Premium and Dedicated tiers.
diagnostic_settings "$NAMESPACE_ID" "[$EVENTHUB_NAMESPACE_NAME] Event Hubs namespace" \
	--export-to-resource-specific true \
	--logs '[
		{"category": "ArchiveLogs", "enabled": true},
		{"category": "OperationalLogs", "enabled": true},
		{"category": "AutoScaleLogs", "enabled": true},
		{"category": "KafkaCoordinatorLogs", "enabled": true},
		{"category": "KafkaUserErrorLogs", "enabled": true},
		{"category": "EventHubVNetConnectionEvent", "enabled": true},
		{"category": "CustomerManagedKeyUserLogs", "enabled": true},
		{"category": "ApplicationMetricsLogs", "enabled": true},
		{"category": "DiagnosticErrorLogs", "enabled": true},
		{"category": "DataDRLogs", "enabled": true}
	]' \
	--metrics '[{"category": "AllMetrics", "enabled": true}]'

# The deliveries the subscription failed to make (AegDeliveryFailureLogs) and the metrics of the topic
diagnostic_settings "$SYSTEM_TOPIC_ID" "[$SYSTEM_TOPIC_NAME] system topic" \
	--logs '[{"category": "DeliveryFailures", "enabled": true}]' \
	--metrics '[{"category": "AllMetrics", "enabled": true}]'

diagnostic_settings "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app" \
	--logs '[{"category": "FunctionAppLogs", "enabled": true}]' \
	--metrics '[{"category": "AllMetrics", "enabled": true}]'

diagnostic_settings "$FUNCTION_PLAN_ID" "plan of the [$FUNCTION_APP_NAME] function app" \
	--metrics '[{"category": "AllMetrics", "enabled": true}]'

# The workspace audits the queries run on it (Audit, table LAQueryLogs)
diagnostic_settings "$LOG_ANALYTICS_ID" "[$LOG_ANALYTICS_NAME] Log Analytics workspace" \
	--logs '[{"category": "Audit", "enabled": true}]' \
	--metrics '[{"category": "AllMetrics", "enabled": true}]'

# -----------------------------------------------------------------------------
step "[11/11] Connection details"
# -----------------------------------------------------------------------------
cat >"$CURRENT_DIR/.deployment-env" <<EOF
export RESOURCE_GROUP_NAME='$RESOURCE_GROUP_NAME'
export EVENTHUB_NAMESPACE_NAME='$EVENTHUB_NAMESPACE_NAME'
export TELEMETRY_HUB_NAME='$TELEMETRY_HUB_NAME'
export NOTIFICATION_HUB_NAME='$NOTIFICATION_HUB_NAME'
export CURATED_HUB_NAME='$CURATED_HUB_NAME'
export CAPTURE_CONSUMER_GROUP='$CAPTURE_CONSUMER_GROUP'
export CAPTURE_CONTAINER_NAME='$CAPTURE_CONTAINER_NAME'
export STORAGE_ACCOUNT_NAME='$STORAGE_ACCOUNT_NAME'
export SYSTEM_TOPIC_NAME='$SYSTEM_TOPIC_NAME'
export SUBSCRIPTION_NAME='$SUBSCRIPTION_NAME'
export FUNCTION_APP_NAME='$FUNCTION_APP_NAME'
export TEMPERATURE_LIMIT='$TEMPERATURE_LIMIT'
export EVENTHUB_SEND_CONNECTION_STRING='$SEND_CONNECTION'
export EVENTHUB_LISTEN_CONNECTION_STRING='$LISTEN_CONNECTION'
export EVENTHUB_NAMESPACE_CONNECTION_STRING='$NAMESPACE_CONNECTION'
export STORAGE_CONNECTION_STRING='$STORAGE_CONNECTION_STRING'
EOF

echo ""
echo "============================================================"
echo "Deployment complete"
echo "============================================================"
echo "Resource group:      $RESOURCE_GROUP_NAME"
echo "Namespace:           $EVENTHUB_NAMESPACE_NAME"
echo "  telemetry hub:     $TELEMETRY_HUB_NAME ($TELEMETRY_PARTITION_COUNT partitions, Capture -> $CAPTURE_CONTAINER_NAME)"
echo "  notifications hub: $NOTIFICATION_HUB_NAME (Event Grid delivers CaptureFileCreated here)"
echo "  curated hub:       $CURATED_HUB_NAME (device summaries)"
echo "System topic:        $SYSTEM_TOPIC_NAME -> subscription '$SUBSCRIPTION_NAME'"
echo "Function App:        $FUNCTION_APP_NAME (consumer group '$CAPTURE_CONSUMER_GROUP')"
echo ""
echo "Next steps:"
echo "  bash scripts/validate.sh        verify every deployed capability"
echo "  bash scripts/run-pipeline.sh    run the end-to-end demo"
