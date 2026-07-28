#!/bin/bash

# =============================================================================
# Real-time payment fraud detection on Azure Event Hubs - deployment
#
# Creates the full topology with the Azure CLI:
#   Log Analytics + Application Insights   telemetry for the Function App
#   Storage account                        Capture archives, checkpoints, function content
#   Event Hubs namespace (Standard, Kafka) the streaming backbone
#     payments      4 partitions, Capture -> Blob (Avro)
#     fraud-alerts  2 partitions
#     consumer groups: fraud-detector, analytics, audit
#     schema group:    payments-schemas
#     send-only / listen-only authorization rules (least privilege)
#   Key Vault                              connection strings kept as secrets
#   Function App (Python)                  Event Hubs trigger -> fraud detection
#   Web App (Python)                       operations dashboard
#
# Everything runs against the LocalStack Azure emulator; no real cloud resources
# are created. Run 'azlocal start-interception' first.
# =============================================================================

# Variables
PREFIX='local'
SUFFIX='payments'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-eventhubs-rg"

EVENTHUB_NAMESPACE_NAME="${PREFIX}-ehns-${SUFFIX}"
EVENT_HUB_NAME='payments'
ALERT_HUB_NAME='fraud-alerts'
PARTITION_COUNT=4
ALERT_PARTITION_COUNT=2
RETENTION_DAYS=1
FRAUD_CONSUMER_GROUP='fraud-detector'
ANALYTICS_CONSUMER_GROUP='analytics'
AUDIT_CONSUMER_GROUP='audit'
SEND_RULE_NAME='payments-send'
LISTEN_RULE_NAME='payments-listen'
ALERT_SEND_RULE_NAME='alerts-send'
DASHBOARD_LISTEN_RULE_NAME='dashboard-listen'
SCHEMA_GROUP_NAME='payments-schemas'

STORAGE_ACCOUNT_NAME="${PREFIX}ehstorage${SUFFIX:0:4}"
CAPTURE_CONTAINER_NAME='payments-archive'
CAPTURE_INTERVAL_SECONDS=60
CAPTURE_SIZE_LIMIT_BYTES=10485760

KEY_VAULT_NAME="${PREFIX}ehkv${SUFFIX:0:4}"
LOG_ANALYTICS_NAME="${PREFIX}-eh-logs"
APP_INSIGHTS_NAME="${PREFIX}-eh-insights"

FUNCTION_APP_NAME="${PREFIX}-eh-fraud-func"
FUNCTION_RUNTIME='python'
FUNCTION_RUNTIME_VERSION='3.12'
FUNCTION_ZIP='fraud_function.zip'

APP_SERVICE_PLAN_NAME="${PREFIX}-eh-plan"
APP_SERVICE_PLAN_SKU='S1'
WEB_APP_NAME="${PREFIX}-eh-dashboard"
WEB_APP_RUNTIME='PYTHON:3.12'
WEB_APP_ZIP='dashboard.zip'

FRAUD_AMOUNT_THRESHOLD=5000
FRAUD_VELOCITY_COUNT=5
FRAUD_VELOCITY_WINDOW_SECONDS=60

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$CURRENT_DIR/../src" && pwd)"

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
step "[1/12] Resource group"
# -----------------------------------------------------------------------------
if ! az group show --name "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az group create \
		--name "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null || fail "could not create resource group [$RESOURCE_GROUP_NAME]"
	echo "Created resource group [$RESOURCE_GROUP_NAME]."
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists."
fi

# -----------------------------------------------------------------------------
step "[2/12] Log Analytics workspace and Application Insights"
# -----------------------------------------------------------------------------
if ! az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" --only-show-errors &>/dev/null; then
	az monitor log-analytics workspace create \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--workspace-name "$LOG_ANALYTICS_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null || fail "could not create Log Analytics workspace"
	echo "Created Log Analytics workspace [$LOG_ANALYTICS_NAME]."
else
	echo "Log Analytics workspace [$LOG_ANALYTICS_NAME] already exists."
fi

WORKSPACE_ID=$(az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query id --output tsv --only-show-errors 2>/dev/null)

if ! az monitor app-insights component show \
	--app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az monitor app-insights component create \
		--app "$APP_INSIGHTS_NAME" \
		--location "$LOCATION" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--application-type web \
		--workspace "$WORKSPACE_ID" \
		--only-show-errors 1>/dev/null || fail "could not create Application Insights"
	echo "Created Application Insights [$APP_INSIGHTS_NAME]."
else
	echo "Application Insights [$APP_INSIGHTS_NAME] already exists."
fi

APP_INSIGHTS_CONNECTION=$(az monitor app-insights component show \
	--app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query connectionString --output tsv --only-show-errors 2>/dev/null)

# -----------------------------------------------------------------------------
step "[3/12] Storage account (capture archives, checkpoints, function content)"
# -----------------------------------------------------------------------------
if ! az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az storage account create \
		--name "$STORAGE_ACCOUNT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--sku Standard_LRS \
		--kind StorageV2 \
		--only-show-errors 1>/dev/null || fail "could not create storage account [$STORAGE_ACCOUNT_NAME]"
	echo "Created storage account [$STORAGE_ACCOUNT_NAME]."
else
	echo "Storage account [$STORAGE_ACCOUNT_NAME] already exists."
fi

# Build the connection string from the account's own endpoints rather than taking the
# EndpointSuffix form. Both are valid against Azure, but only the explicit-endpoint form
# survives a non-default port, which the Azure Functions host (a .NET workload) requires
# to parse AzureWebJobsStorage at all.
STORAGE_KEY=$(az storage account keys list \
	--account-name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[0].value" --output tsv --only-show-errors)
STORAGE_BLOB_ENDPOINT=$(az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryEndpoints.blob --output tsv --only-show-errors)
STORAGE_QUEUE_ENDPOINT=$(az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryEndpoints.queue --output tsv --only-show-errors)
STORAGE_TABLE_ENDPOINT=$(az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryEndpoints.table --output tsv --only-show-errors)
[[ -n "$STORAGE_KEY" && -n "$STORAGE_BLOB_ENDPOINT" ]] || fail "could not read the storage account keys/endpoints"

STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_KEY};BlobEndpoint=${STORAGE_BLOB_ENDPOINT};QueueEndpoint=${STORAGE_QUEUE_ENDPOINT};TableEndpoint=${STORAGE_TABLE_ENDPOINT}"

STORAGE_ACCOUNT_ID=$(az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query id --output tsv --only-show-errors)

az storage container create \
	--name "$CAPTURE_CONTAINER_NAME" \
	--connection-string "$STORAGE_CONNECTION_STRING" \
	--only-show-errors 1>/dev/null || fail "could not create the capture container"
echo "Created blob container [$CAPTURE_CONTAINER_NAME] for Capture archives."

# -----------------------------------------------------------------------------
step "[4/12] Event Hubs namespace (Standard tier, Kafka enabled)"
# -----------------------------------------------------------------------------
if ! az eventhubs namespace show \
	--name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az eventhubs namespace create \
		--name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--sku Standard \
		--enable-kafka true \
		--enable-auto-inflate true \
		--maximum-throughput-units 4 \
		--only-show-errors 1>/dev/null || fail "could not create the Event Hubs namespace"
	echo "Created Event Hubs namespace [$EVENTHUB_NAMESPACE_NAME] (Kafka enabled, auto-inflate to 4 TU)."
else
	echo "Event Hubs namespace [$EVENTHUB_NAMESPACE_NAME] already exists."
fi

# -----------------------------------------------------------------------------
step "[5/12] Event hubs: '$EVENT_HUB_NAME' (with Capture) and '$ALERT_HUB_NAME'"
# -----------------------------------------------------------------------------
if ! az eventhubs eventhub show \
	--name "$EVENT_HUB_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	# Capture writes an Avro archive per partition on whichever limit is reached first
	# (time or size). skip-empty-archives keeps idle windows from producing empty blobs.
	az eventhubs eventhub create \
		--name "$EVENT_HUB_NAME" \
		--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--partition-count "$PARTITION_COUNT" \
		--retention-time-in-hours $((RETENTION_DAYS * 24)) \
		--cleanup-policy Delete \
		--enable-capture true \
		--capture-interval "$CAPTURE_INTERVAL_SECONDS" \
		--capture-size-limit "$CAPTURE_SIZE_LIMIT_BYTES" \
		--skip-empty-archives true \
		--destination-name EventHubArchive.AzureBlockBlob \
		--storage-account "$STORAGE_ACCOUNT_ID" \
		--blob-container "$CAPTURE_CONTAINER_NAME" \
		--archive-name-format '{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}' \
		--only-show-errors 1>/dev/null || fail "could not create event hub [$EVENT_HUB_NAME]"
	echo "Created event hub [$EVENT_HUB_NAME] with $PARTITION_COUNT partitions and Capture enabled."
else
	echo "Event hub [$EVENT_HUB_NAME] already exists."
fi

if ! az eventhubs eventhub show \
	--name "$ALERT_HUB_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az eventhubs eventhub create \
		--name "$ALERT_HUB_NAME" \
		--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--partition-count "$ALERT_PARTITION_COUNT" \
		--retention-time-in-hours $((RETENTION_DAYS * 24)) \
		--only-show-errors 1>/dev/null || fail "could not create event hub [$ALERT_HUB_NAME]"
	echo "Created event hub [$ALERT_HUB_NAME] with $ALERT_PARTITION_COUNT partitions."
else
	echo "Event hub [$ALERT_HUB_NAME] already exists."
fi

# -----------------------------------------------------------------------------
step "[6/12] Consumer groups"
# -----------------------------------------------------------------------------
# Each downstream system gets its own consumer group, so they read the same stream at
# their own pace with independent offsets - the reason a log beats a queue here.
for consumer_group in "$FRAUD_CONSUMER_GROUP" "$ANALYTICS_CONSUMER_GROUP" "$AUDIT_CONSUMER_GROUP"; do
	if ! az eventhubs eventhub consumer-group show \
		--consumer-group-name "$consumer_group" \
		--eventhub-name "$EVENT_HUB_NAME" \
		--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
		az eventhubs eventhub consumer-group create \
			--consumer-group-name "$consumer_group" \
			--eventhub-name "$EVENT_HUB_NAME" \
			--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--only-show-errors 1>/dev/null || fail "could not create consumer group [$consumer_group]"
		echo "Created consumer group [$consumer_group]."
	else
		echo "Consumer group [$consumer_group] already exists."
	fi
done

# -----------------------------------------------------------------------------
step "[7/12] Authorization rules (least privilege)"
# -----------------------------------------------------------------------------
# Producers get Send, consumers get Listen. Handing every workload the namespace-wide
# Manage key is the most common Event Hubs security mistake.
if ! az eventhubs eventhub authorization-rule show \
	--name "$SEND_RULE_NAME" --eventhub-name "$EVENT_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null; then
	az eventhubs eventhub authorization-rule create \
		--name "$SEND_RULE_NAME" \
		--eventhub-name "$EVENT_HUB_NAME" \
		--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--rights Send \
		--only-show-errors 1>/dev/null || fail "could not create rule [$SEND_RULE_NAME]"
	echo "Created send-only authorization rule [$SEND_RULE_NAME]."
else
	echo "Authorization rule [$SEND_RULE_NAME] already exists."
fi

# The alerts hub needs its own send rule. An entity-level rule's connection string carries
# EntityPath, which pins every client using it to that entity - so the payments rule cannot
# publish alerts, and a binding configured with it would silently write back into
# 'payments'.
if ! az eventhubs eventhub authorization-rule show \
	--name "$ALERT_SEND_RULE_NAME" --eventhub-name "$ALERT_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null; then
	az eventhubs eventhub authorization-rule create \
		--name "$ALERT_SEND_RULE_NAME" \
		--eventhub-name "$ALERT_HUB_NAME" \
		--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--rights Send \
		--only-show-errors 1>/dev/null || fail "could not create rule [$ALERT_SEND_RULE_NAME]"
	echo "Created send-only authorization rule [$ALERT_SEND_RULE_NAME] on the alerts hub."
else
	echo "Authorization rule [$ALERT_SEND_RULE_NAME] already exists."
fi

if ! az eventhubs eventhub authorization-rule show \
	--name "$LISTEN_RULE_NAME" --eventhub-name "$EVENT_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null; then
	az eventhubs eventhub authorization-rule create \
		--name "$LISTEN_RULE_NAME" \
		--eventhub-name "$EVENT_HUB_NAME" \
		--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--rights Listen \
		--only-show-errors 1>/dev/null || fail "could not create rule [$LISTEN_RULE_NAME]"
	echo "Created listen-only authorization rule [$LISTEN_RULE_NAME]."
else
	echo "Authorization rule [$LISTEN_RULE_NAME] already exists."
fi

# The dashboard reads both hubs plus partition runtime metadata, which an entity-level rule
# on one hub cannot cover - but that is a reason for a namespace-level *Listen* rule, not for
# handing a reader the namespace Manage key.
if ! az eventhubs namespace authorization-rule show \
	--name "$DASHBOARD_LISTEN_RULE_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az eventhubs namespace authorization-rule create \
		--name "$DASHBOARD_LISTEN_RULE_NAME" \
		--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--rights Listen \
		--only-show-errors 1>/dev/null || fail "could not create rule [$DASHBOARD_LISTEN_RULE_NAME]"
	echo "Created namespace-wide listen-only rule [$DASHBOARD_LISTEN_RULE_NAME] for the dashboard."
else
	echo "Authorization rule [$DASHBOARD_LISTEN_RULE_NAME] already exists."
fi

# -----------------------------------------------------------------------------
step "[8/12] Schema Registry group"
# -----------------------------------------------------------------------------
if ! az eventhubs namespace schema-registry show \
	--name "$SCHEMA_GROUP_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az eventhubs namespace schema-registry create \
		--name "$SCHEMA_GROUP_NAME" \
		--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--schema-compatibility Forward \
		--schema-type Avro \
		--only-show-errors 1>/dev/null || fail "could not create schema group [$SCHEMA_GROUP_NAME]"
	echo "Created schema group [$SCHEMA_GROUP_NAME] (Avro, forward compatibility)."
else
	echo "Schema group [$SCHEMA_GROUP_NAME] already exists."
fi

# -----------------------------------------------------------------------------
step "[9/12] Connection strings and Key Vault"
# -----------------------------------------------------------------------------
EVENTHUB_SEND_CONNECTION_STRING=$(az eventhubs eventhub authorization-rule keys list \
	--name "$SEND_RULE_NAME" --eventhub-name "$EVENT_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryConnectionString --output tsv --only-show-errors)
EVENTHUB_LISTEN_CONNECTION_STRING=$(az eventhubs eventhub authorization-rule keys list \
	--name "$LISTEN_RULE_NAME" --eventhub-name "$EVENT_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryConnectionString --output tsv --only-show-errors)
EVENTHUB_ALERT_SEND_CONNECTION_STRING=$(az eventhubs eventhub authorization-rule keys list \
	--name "$ALERT_SEND_RULE_NAME" --eventhub-name "$ALERT_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryConnectionString --output tsv --only-show-errors)
EVENTHUB_NAMESPACE_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
	--name RootManageSharedAccessKey --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryConnectionString --output tsv --only-show-errors)
DASHBOARD_LISTEN_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
	--name "$DASHBOARD_LISTEN_RULE_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryConnectionString --output tsv --only-show-errors)

# Every one of these is a credential something downstream depends on, so an empty value has
# to stop the deployment here rather than surface as a puzzling runtime failure later.
[[ -n "$EVENTHUB_SEND_CONNECTION_STRING" ]] || fail "could not read the send connection string"
[[ -n "$EVENTHUB_LISTEN_CONNECTION_STRING" ]] || fail "could not read the listen connection string"
[[ -n "$EVENTHUB_ALERT_SEND_CONNECTION_STRING" ]] || fail "could not read the alerts send connection string"
[[ -n "$EVENTHUB_NAMESPACE_CONNECTION_STRING" ]] || fail "could not read the namespace connection string"
[[ -n "$DASHBOARD_LISTEN_CONNECTION_STRING" ]] || fail "could not read the dashboard listen connection string"

if ! az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az keyvault create \
		--name "$KEY_VAULT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1>/dev/null || fail "could not create key vault [$KEY_VAULT_NAME]"
	echo "Created key vault [$KEY_VAULT_NAME]."
else
	echo "Key vault [$KEY_VAULT_NAME] already exists."
fi

# Secrets, not app settings, are where connection strings belong.
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name eventhub-send-connection \
	--value "$EVENTHUB_SEND_CONNECTION_STRING" --only-show-errors 1>/dev/null || fail "could not store the send secret"
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name eventhub-listen-connection \
	--value "$EVENTHUB_LISTEN_CONNECTION_STRING" --only-show-errors 1>/dev/null || fail "could not store the listen secret"
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name storage-connection \
	--value "$STORAGE_CONNECTION_STRING" --only-show-errors 1>/dev/null || fail "could not store the storage secret"
echo "Stored three connection strings as Key Vault secrets."

# -----------------------------------------------------------------------------
step "[10/12] Function App (Event Hubs trigger -> fraud detection)"
# -----------------------------------------------------------------------------
if ! az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az functionapp create \
		--name "$FUNCTION_APP_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--consumption-plan-location "$LOCATION" \
		--runtime "$FUNCTION_RUNTIME" \
		--runtime-version "$FUNCTION_RUNTIME_VERSION" \
		--functions-version 4 \
		--os-type linux \
		--storage-account "$STORAGE_ACCOUNT_NAME" \
		--only-show-errors 1>/dev/null || fail "could not create function app [$FUNCTION_APP_NAME]"
	echo "Created function app [$FUNCTION_APP_NAME]."
else
	echo "Function app [$FUNCTION_APP_NAME] already exists."
fi

FUNCTION_SETTINGS=(
	# The Functions host reads its own state (leases, checkpoints) through this setting.
	"AzureWebJobsStorage=$STORAGE_CONNECTION_STRING"
	"EVENTHUB_LISTEN_CONNECTION=$EVENTHUB_LISTEN_CONNECTION_STRING"
	# Scoped to the alerts hub: the payments rule would pin the binding to "payments"
	"EVENTHUB_SEND_CONNECTION=$EVENTHUB_ALERT_SEND_CONNECTION_STRING"
	"EVENT_HUB_NAME=$EVENT_HUB_NAME"
	"ALERT_HUB_NAME=$ALERT_HUB_NAME"
	"FRAUD_CONSUMER_GROUP=$FRAUD_CONSUMER_GROUP"
	"FRAUD_AMOUNT_THRESHOLD=$FRAUD_AMOUNT_THRESHOLD"
	"FRAUD_VELOCITY_COUNT=$FRAUD_VELOCITY_COUNT"
	"FRAUD_VELOCITY_WINDOW_SECONDS=$FRAUD_VELOCITY_WINDOW_SECONDS"
)
if [[ -n "$APP_INSIGHTS_CONNECTION" ]]; then
	FUNCTION_SETTINGS+=("APPLICATIONINSIGHTS_CONNECTION_STRING=$APP_INSIGHTS_CONNECTION")
fi

az functionapp config appsettings set \
	--name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--settings "${FUNCTION_SETTINGS[@]}" \
	--only-show-errors 1>/dev/null || fail "could not set function app settings"
echo "Configured function app settings."

cd "$SRC_DIR/functions" || fail "missing src/functions"
rm -f "$CURRENT_DIR/$FUNCTION_ZIP"
zip -r "$CURRENT_DIR/$FUNCTION_ZIP" function_app.py host.json requirements.txt 1>/dev/null
cd "$CURRENT_DIR" || exit 1

echo "Deploying the function package (first run pulls the build image and can take a few minutes)..."
az functionapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--src-path "$FUNCTION_ZIP" \
	--type zip 1>/dev/null || fail "could not deploy the function app"
rm -f "$FUNCTION_ZIP"
echo "Deployed the fraud detection function."

# -----------------------------------------------------------------------------
step "[11/12] Web App (operations dashboard)"
# -----------------------------------------------------------------------------
if ! az appservice plan show --name "$APP_SERVICE_PLAN_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az appservice plan create \
		--name "$APP_SERVICE_PLAN_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--sku "$APP_SERVICE_PLAN_SKU" \
		--is-linux \
		--only-show-errors 1>/dev/null || fail "could not create the app service plan"
	echo "Created app service plan [$APP_SERVICE_PLAN_NAME]."
else
	echo "App service plan [$APP_SERVICE_PLAN_NAME] already exists."
fi

if ! az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null; then
	az webapp create \
		--name "$WEB_APP_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--plan "$APP_SERVICE_PLAN_NAME" \
		--runtime "$WEB_APP_RUNTIME" \
		--only-show-errors 1>/dev/null || fail "could not create web app [$WEB_APP_NAME]"
	echo "Created web app [$WEB_APP_NAME]."
else
	echo "Web app [$WEB_APP_NAME] already exists."
fi

az webapp config appsettings set \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--settings \
	"EVENTHUB_LISTEN_CONNECTION_STRING=$DASHBOARD_LISTEN_CONNECTION_STRING" \
	"STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING" \
	"EVENT_HUB_NAME=$EVENT_HUB_NAME" \
	"ALERT_HUB_NAME=$ALERT_HUB_NAME" \
	"FRAUD_CONSUMER_GROUP=$FRAUD_CONSUMER_GROUP" \
	"CAPTURE_CONTAINER_NAME=$CAPTURE_CONTAINER_NAME" \
	"SCHEMA_GROUP_NAME=$SCHEMA_GROUP_NAME" \
	"SCM_DO_BUILD_DURING_DEPLOYMENT=true" \
	--only-show-errors 1>/dev/null || fail "could not set web app settings"

az webapp config set \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--startup-file "gunicorn --config gunicorn.conf.py app:app" \
	--only-show-errors 1>/dev/null || fail "could not set the dashboard startup command"

cd "$SRC_DIR/dashboard" || fail "missing src/dashboard"
rm -f "$CURRENT_DIR/$WEB_APP_ZIP"
zip -r "$CURRENT_DIR/$WEB_APP_ZIP" app.py gunicorn.conf.py requirements.txt templates static 1>/dev/null
cd "$CURRENT_DIR" || exit 1

echo "Deploying the dashboard package..."
az webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$WEB_APP_ZIP" \
	--type zip 1>/dev/null || fail "could not deploy the web app"
rm -f "$WEB_APP_ZIP"
echo "Deployed the operations dashboard."

# -----------------------------------------------------------------------------
step "[12/12] Connection details"
# -----------------------------------------------------------------------------
WEB_APP_URL=$(az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query defaultHostName --output tsv --only-show-errors 2>/dev/null)

# The producers read these from the environment; scripts/run-pipeline.sh sources this file.
cat >"$CURRENT_DIR/.deployment-env" <<EOF
export RESOURCE_GROUP_NAME='$RESOURCE_GROUP_NAME'
export EVENTHUB_NAMESPACE_NAME='$EVENTHUB_NAMESPACE_NAME'
export EVENT_HUB_NAME='$EVENT_HUB_NAME'
export ALERT_HUB_NAME='$ALERT_HUB_NAME'
export FRAUD_CONSUMER_GROUP='$FRAUD_CONSUMER_GROUP'
export SCHEMA_GROUP_NAME='$SCHEMA_GROUP_NAME'
export STORAGE_ACCOUNT_NAME='$STORAGE_ACCOUNT_NAME'
export CAPTURE_CONTAINER_NAME='$CAPTURE_CONTAINER_NAME'
export KEY_VAULT_NAME='$KEY_VAULT_NAME'
export FUNCTION_APP_NAME='$FUNCTION_APP_NAME'
export WEB_APP_NAME='$WEB_APP_NAME'
export EVENTHUB_SEND_CONNECTION_STRING='$EVENTHUB_SEND_CONNECTION_STRING'
export EVENTHUB_LISTEN_CONNECTION_STRING='$EVENTHUB_LISTEN_CONNECTION_STRING'
export EVENTHUB_ALERT_SEND_CONNECTION_STRING='$EVENTHUB_ALERT_SEND_CONNECTION_STRING'
export EVENTHUB_NAMESPACE_CONNECTION_STRING='$EVENTHUB_NAMESPACE_CONNECTION_STRING'
export STORAGE_CONNECTION_STRING='$STORAGE_CONNECTION_STRING'
EOF

echo ""
echo "============================================================"
echo "Deployment complete"
echo "============================================================"
echo "Resource group:      $RESOURCE_GROUP_NAME"
echo "Event Hubs namespace:$EVENTHUB_NAMESPACE_NAME"
echo "  payments hub:      $EVENT_HUB_NAME ($PARTITION_COUNT partitions, Capture -> $CAPTURE_CONTAINER_NAME)"
echo "  alerts hub:        $ALERT_HUB_NAME ($ALERT_PARTITION_COUNT partitions)"
echo "  consumer groups:   $FRAUD_CONSUMER_GROUP, $ANALYTICS_CONSUMER_GROUP, $AUDIT_CONSUMER_GROUP"
echo "  schema group:      $SCHEMA_GROUP_NAME"
echo "Function App:        $FUNCTION_APP_NAME"
echo "Dashboard:           https://${WEB_APP_URL:-<pending>}"
echo ""
echo "Next steps:"
echo "  bash scripts/validate.sh        verify every deployed capability"
echo "  bash scripts/run-pipeline.sh    run the end-to-end demo"
echo ""
