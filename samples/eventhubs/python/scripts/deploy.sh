#!/bin/bash

# =============================================================================
# Real-time payment fraud detection on Azure Event Hubs - deployment
#
# Creates the full topology with the Azure CLI:
#   Log Analytics + Application Insights   telemetry for the Function App and the Web App
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
#   Diagnostic settings                    resource logs and metrics of every resource -> Log Analytics
#
# Everything runs against the LocalStack Azure emulator; no real cloud resources
# are created. Run 'lstk az start-interception' first.
# =============================================================================

# Variables
PREFIX="${PREFIX:-local}"
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
DIAGNOSTIC_SETTINGS_NAME='default'
KEY_VAULT_SECRETS_OFFICER_ROLE='Key Vault Secrets Officer'
ROLE_ASSIGNMENT_RETRY_COUNT=3
ROLE_ASSIGNMENT_RETRY_SLEEP=5
SECRET_RETRY_COUNT=20
SECRET_RETRY_SLEEP=15

FUNCTION_APP_NAME="${PREFIX}-eh-fraud-func"
FUNCTION_RUNTIME='python'
FUNCTION_RUNTIME_VERSION='3.12'
FUNCTION_ZIP='fraud_function.zip'
DEPLOY_RETRY_COUNT=10
DEPLOY_RETRY_SLEEP=60

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

# Create the diagnostic settings of a resource that sends its resource logs and its platform metrics to the Log
# Analytics workspace, unless they already exist
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
		--workspace "$WORKSPACE_ID" \
		"$@" \
		--only-show-errors 1>/dev/null || fail "could not create the diagnostic settings of the $description"
	echo "Created the diagnostic settings of the $description."
}

# Assign a role to a principal at a scope, unless the assignment already exists. The assignee is given as an object id
# together with its principal type, so no directory lookup happens at creation time.
# $1: the object id of the principal
# $2: the principal type (ServicePrincipal, User or Group)
# $3: the role name
# $4: the scope (resource id)
# $5: the description of the principal and the scope, used in messages
ensure_role_assignment() {
	local principal_id=$1
	local principal_type=$2
	local role=$3
	local scope=$4
	local description=$5
	local current attempt

	current=$(az role assignment list --assignee "$principal_id" --scope "$scope" \
		--query "[?roleDefinitionName=='$role'].roleDefinitionName" --output tsv --only-show-errors 2>/dev/null)
	if [[ $current == "$role" ]]; then
		echo "The [$role] role is already assigned to the $description."
		return 0
	fi

	for attempt in $(seq 1 "$ROLE_ASSIGNMENT_RETRY_COUNT"); do
		if az role assignment create \
			--assignee-object-id "$principal_id" \
			--assignee-principal-type "$principal_type" \
			--role "$role" \
			--scope "$scope" \
			--only-show-errors 1>/dev/null; then
			echo "Assigned the [$role] role to the $description."
			return 0
		fi
		if [ "$attempt" -lt "$ROLE_ASSIGNMENT_RETRY_COUNT" ]; then
			echo "Attempt $attempt of $ROLE_ASSIGNMENT_RETRY_COUNT to assign the [$role] role failed. Waiting [$ROLE_ASSIGNMENT_RETRY_SLEEP] seconds before retry..."
			sleep "$ROLE_ASSIGNMENT_RETRY_SLEEP"
		fi
	done
	fail "could not assign the [$role] role to the $description"
}

# Store a secret in the key vault, unless it already holds the same value. The deploying principal can write through the Key Vault data plane only once its
# Key Vault Secrets Officer assignment has propagated, which takes a few minutes on Azure, so the write is retried. The
# value is never printed.
# $1: the secret name
# $2: the secret value
set_secret() {
	local secret_name=$1
	local secret_value=$2
	local attempt error current

	current=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$secret_name" \
		--query value --output tsv --only-show-errors 2>/dev/null)
	if [[ -n $current && $current == "$secret_value" ]]; then
		echo "The [$secret_name] secret already holds the expected value."
		return 0
	fi

	for attempt in $(seq 1 "$SECRET_RETRY_COUNT"); do
		if error=$(az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "$secret_name" \
			--value "$secret_value" --only-show-errors 2>&1 1>/dev/null); then
			return 0
		fi
		if [ "$attempt" -lt "$SECRET_RETRY_COUNT" ]; then
			echo "Attempt $attempt of $SECRET_RETRY_COUNT: the [$secret_name] secret could not be stored yet. Waiting [$SECRET_RETRY_SLEEP] seconds before retry..."
			sleep "$SECRET_RETRY_SLEEP"
		fi
	done
	echo "$error"
	fail "could not store the [$secret_name] secret"
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
[[ -n "$WORKSPACE_ID" ]] || fail "could not read the Log Analytics workspace id"
[[ -n "$APP_INSIGHTS_CONNECTION" ]] || fail "could not read the Application Insights connection string"

# The workspace audits the queries run on it (Audit, table LAQueryLogs)
diagnostic_settings "$WORKSPACE_ID" "[$LOG_ANALYTICS_NAME] Log Analytics workspace" \
	--logs '[{"category": "Audit", "enabled": true}]' \
	--metrics '[{"category": "AllMetrics", "enabled": true}]'

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
[[ -n "$STORAGE_ACCOUNT_ID" ]] || fail "could not read the storage account id"

# The storage account offers metrics only; its services send the logs of their requests and their metrics
diagnostic_settings "$STORAGE_ACCOUNT_ID" "[$STORAGE_ACCOUNT_NAME] storage account" \
	--metrics '[{"category": "Capacity", "enabled": true}, {"category": "Transaction", "enabled": true}]'
for SERVICE in blob queue table; do
	diagnostic_settings "$STORAGE_ACCOUNT_ID/${SERVICE}Services/default" "$SERVICE service of the [$STORAGE_ACCOUNT_NAME] storage account" \
		--logs '[{"category": "StorageRead", "enabled": true}, {"category": "StorageWrite", "enabled": true}, {"category": "StorageDelete", "enabled": true}]' \
		--metrics '[{"category": "Capacity", "enabled": true}, {"category": "Transaction", "enabled": true}]'
done

if [[ $(az storage container exists --name "$CAPTURE_CONTAINER_NAME" --connection-string "$STORAGE_CONNECTION_STRING" \
	--query exists --output tsv --only-show-errors 2>/dev/null | tr -d '\r') == "true" ]]; then
	echo "Blob container [$CAPTURE_CONTAINER_NAME] for Capture archives already exists."
else
	az storage container create \
		--name "$CAPTURE_CONTAINER_NAME" \
		--connection-string "$STORAGE_CONNECTION_STRING" \
		--only-show-errors 1>/dev/null || fail "could not create the capture container"
	echo "Created blob container [$CAPTURE_CONTAINER_NAME] for Capture archives."
fi

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

EVENTHUB_NAMESPACE_ID=$(az eventhubs namespace show --name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors)
[[ -n "$EVENTHUB_NAMESPACE_ID" ]] || fail "could not read the Event Hubs namespace id"

# The namespace writes its operational logs to the resource-specific AZMSOperationalLogs table; its other categories
# have AzureDiagnostics only. Created before the event hubs, so that
# the operational logs record their creation. ArchiveLogs records the Capture archives; the runtime audit logs are left
# out, since Event Hubs writes them only in the Premium and Dedicated tiers.
diagnostic_settings "$EVENTHUB_NAMESPACE_ID" "[$EVENTHUB_NAMESPACE_NAME] Event Hubs namespace" \
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
		--cleanup-policy Delete \
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

KEY_VAULT_ID=$(az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query id --output tsv --only-show-errors)
[[ -n "$KEY_VAULT_ID" ]] || fail "could not read the key vault id"

# The operations on the vault and its secrets, among them the writes below and the reads of validate.sh (AZKVAuditLogs)
diagnostic_settings "$KEY_VAULT_ID" "[$KEY_VAULT_NAME] key vault" \
	--export-to-resource-specific true \
	--logs '[{"category": "AuditEvent", "enabled": true}, {"category": "AzurePolicyEvaluationDetails", "enabled": true}]' \
	--metrics '[{"category": "AllMetrics", "enabled": true}]'

# Resolve the object id of the deploying principal, a user or a service principal. The vault uses the RBAC permission
# model, so writing the secrets needs the Key Vault Secrets Officer role on the vault. The lookup goes through Microsoft
# Graph, with the oid claim of the CLI's own access token as the fallback for a principal that lacks directory
# permissions; when both fail the role must already be assigned.
ACCOUNT_USER_TYPE=$(az account show --query user.type --output tsv --only-show-errors)
ACCOUNT_USER_NAME=$(az account show --query user.name --output tsv --only-show-errors)

if [[ $ACCOUNT_USER_TYPE == "user" ]]; then
	DEPLOYER_PRINCIPAL_TYPE="User"
	DEPLOYER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv --only-show-errors 2>/dev/null)
else
	DEPLOYER_PRINCIPAL_TYPE="ServicePrincipal"
	DEPLOYER_OBJECT_ID=$(az ad sp show --id "$ACCOUNT_USER_NAME" --query id --output tsv --only-show-errors 2>/dev/null)
fi

if [[ -z $DEPLOYER_OBJECT_ID ]]; then
	DEPLOYER_OBJECT_ID=$(az account get-access-token --query accessToken --output tsv --only-show-errors 2>/dev/null |
		cut -d. -f2 | tr '_-' '/+' | awk '{ pad = length($0) % 4; if (pad == 2) $0 = $0 "=="; else if (pad == 3) $0 = $0 "="; print }' |
		base64 -d 2>/dev/null | jq -r '.oid // empty' 2>/dev/null)
fi

if [[ -n $DEPLOYER_OBJECT_ID ]]; then
	echo "Deploying principal [$ACCOUNT_USER_NAME] ($DEPLOYER_PRINCIPAL_TYPE) has object id [$DEPLOYER_OBJECT_ID]."
else
	echo "WARNING: could not resolve the object id of the deploying principal [$ACCOUNT_USER_NAME]; the [$KEY_VAULT_SECRETS_OFFICER_ROLE] role on the key vault must already be assigned to it."
fi
if [[ -n $DEPLOYER_OBJECT_ID ]]; then
	ensure_role_assignment "$DEPLOYER_OBJECT_ID" "$DEPLOYER_PRINCIPAL_TYPE" "$KEY_VAULT_SECRETS_OFFICER_ROLE" "$KEY_VAULT_ID" \
		"deploying principal [$ACCOUNT_USER_NAME] on the [$KEY_VAULT_NAME] key vault"
fi

# Secrets, not app settings, are where connection strings belong.
set_secret eventhub-send-connection "$EVENTHUB_SEND_CONNECTION_STRING"
set_secret eventhub-listen-connection "$EVENTHUB_LISTEN_CONNECTION_STRING"
set_secret storage-connection "$STORAGE_CONNECTION_STRING"
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
		--app-insights "$APP_INSIGHTS_NAME" \
		--os-type linux \
		--storage-account "$STORAGE_ACCOUNT_NAME" \
		--only-show-errors 1>/dev/null || fail "could not create function app [$FUNCTION_APP_NAME]"
	echo "Created function app [$FUNCTION_APP_NAME]."
else
	echo "Function app [$FUNCTION_APP_NAME] already exists."
fi

FUNCTION_APP_ID=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query id --output tsv --only-show-errors)
# The Consumption plan az functionapp create made for the app, whose name Azure picks
FUNCTION_PLAN_ID=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query appServicePlanId --output tsv --only-show-errors)
[[ -n "$FUNCTION_APP_ID" && -n "$FUNCTION_PLAN_ID" ]] || fail "could not read the ids of the function app and its plan"

# The records the Functions host writes for each invocation (FunctionAppLogs), before the package is deployed
diagnostic_settings "$FUNCTION_APP_ID" "[$FUNCTION_APP_NAME] function app" \
	--logs '[{"category": "FunctionAppLogs", "enabled": true}]' \
	--metrics '[{"category": "AllMetrics", "enabled": true}]'
diagnostic_settings "$FUNCTION_PLAN_ID" "plan of the [$FUNCTION_APP_NAME] function app" \
	--metrics '[{"category": "AllMetrics", "enabled": true}]'

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
# function_app.py configures the Azure Monitor OpenTelemetry Distro itself with this connection string
FUNCTION_SETTINGS+=(
	"APPLICATIONINSIGHTS_CONNECTION_STRING=$APP_INSIGHTS_CONNECTION"
)

az functionapp config appsettings set \
	--name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--settings "${FUNCTION_SETTINGS[@]}" \
	--only-show-errors 1>/dev/null || fail "could not set function app settings"
echo "Configured function app settings."

cd "$SRC_DIR/functions" || fail "missing src/functions"
rm -f "$CURRENT_DIR/$FUNCTION_ZIP"
zip -r "$(native_path "$CURRENT_DIR/$FUNCTION_ZIP")" function_app.py host.json requirements.txt 1>/dev/null
cd "$CURRENT_DIR" || exit 1

echo "Deploying the function package (first run pulls the build image and can take a few minutes)..."
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

APP_SERVICE_PLAN_ID=$(az appservice plan show --name "$APP_SERVICE_PLAN_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query id --output tsv --only-show-errors)
[[ -n "$APP_SERVICE_PLAN_ID" ]] || fail "could not read the App Service plan id"
diagnostic_settings "$APP_SERVICE_PLAN_ID" "[$APP_SERVICE_PLAN_NAME] App Service plan" \
	--metrics '[{"category": "AllMetrics", "enabled": true}]'

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

WEB_APP_ID=$(az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query id --output tsv --only-show-errors)
[[ -n "$WEB_APP_ID" ]] || fail "could not read the web app id"

# The requests, console output and platform events of the dashboard, before the package is deployed, so that the
# container start it causes is logged too
diagnostic_settings "$WEB_APP_ID" "[$WEB_APP_NAME] web app" \
	--logs '[
		{"category": "AppServiceHTTPLogs", "enabled": true},
		{"category": "AppServiceConsoleLogs", "enabled": true},
		{"category": "AppServiceAppLogs", "enabled": true},
		{"category": "AppServiceAuditLogs", "enabled": true},
		{"category": "AppServiceIPSecAuditLogs", "enabled": true},
		{"category": "AppServicePlatformLogs", "enabled": true},
		{"category": "AppServiceAuthenticationLogs", "enabled": true}
	]' \
	--metrics '[{"category": "AllMetrics", "enabled": true}]'

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
	"APPLICATIONINSIGHTS_CONNECTION_STRING=$APP_INSIGHTS_CONNECTION" \
	"SCM_DO_BUILD_DURING_DEPLOYMENT=true" \
	--only-show-errors 1>/dev/null || fail "could not set web app settings"

# No custom startup command: App Service starts Gunicorn for the Flask app in app.py, and Gunicorn reads
# gunicorn.conf.py from the app folder. With a custom command, a container that starts before the package is
# deployed exits at once ('gunicorn.conf.py' doesn't exist), and on Azure the deployment can then report that the
# site failed to start
cd "$SRC_DIR/dashboard" || fail "missing src/dashboard"
rm -f "$CURRENT_DIR/$WEB_APP_ZIP"
zip -r "$(native_path "$CURRENT_DIR/$WEB_APP_ZIP")" app.py gunicorn.conf.py requirements.txt templates static 1>/dev/null
cd "$CURRENT_DIR" || exit 1

echo "Deploying the dashboard package..."
# Asynchronous, as in the other web app samples: the CLI polls the deployment until the build ends. A synchronous
# request timed out on Azure (504) while the build was still running
# On Azure the deployment service can answer 504 Gateway Timeout while it warms up, or DeploymentInProgress while
# the build of the previous deployment still runs: the upload is tried again. The startup of the site isn't
# tracked: the tracking counted a failed start of the container that ran before the code was deployed, and
# reported a running site as failed after ten minutes; what calls the web app afterwards waits for it instead.
WEBAPP_DEPLOY_RETRY_COUNT="${WEBAPP_DEPLOY_RETRY_COUNT:-10}"
WEBAPP_DEPLOY_RETRY_SLEEP="${WEBAPP_DEPLOY_RETRY_SLEEP:-30}"
WEBAPP_DEPLOYED=0
for ATTEMPT in $(seq 1 "$WEBAPP_DEPLOY_RETRY_COUNT"); do
	if az webapp deploy \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$WEB_APP_NAME" \
		--src-path "$WEB_APP_ZIP" \
		--type zip \
		--async true \
		--track-status false 1>/dev/null; then
		WEBAPP_DEPLOYED=1
		break
	fi
	if [ "$ATTEMPT" -lt "$WEBAPP_DEPLOY_RETRY_COUNT" ]; then
		echo "Attempt $ATTEMPT of $WEBAPP_DEPLOY_RETRY_COUNT to deploy web app [$WEB_APP_NAME] failed. Waiting [$WEBAPP_DEPLOY_RETRY_SLEEP] seconds before retry..."
		sleep "$WEBAPP_DEPLOY_RETRY_SLEEP"
	fi
done
[[ $WEBAPP_DEPLOYED == 1 ]] || fail "could not deploy the web app"
rm -f "$WEB_APP_ZIP"
echo "Deployed the operations dashboard."

# A function app on the Consumption plan runs only when the platform's scale controller starts it for the events its
# trigger watches. On Azure, after two deployments in a row, the scale controller watched no trigger and never started
# the function app (2026-11-26). Registering the triggers again at the end of the deployment, once the remote build of
# the package has had time to finish, makes it start the function app when the events arrive.
WEB_API_VERSION="${WEB_API_VERSION:-2024-04-01}"
echo "Syncing the triggers of the [$FUNCTION_APP_NAME] function app..."
FUNCTION_APP_ID=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query id --output tsv --only-show-errors)
[[ -n "$FUNCTION_APP_ID" ]] || fail "could not read the id of function app [$FUNCTION_APP_NAME]"
az rest --method post --url "$FUNCTION_APP_ID/syncfunctiontriggers?api-version=$WEB_API_VERSION" --only-show-errors \
	1>/dev/null || fail "could not sync the triggers of function app [$FUNCTION_APP_NAME]"
echo "Synced the triggers of the [$FUNCTION_APP_NAME] function app."

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
echo "  bash scripts/validate.sh                  verify every deployed capability"
echo "  bash scripts/run-pipeline.sh              run the end-to-end demo"
echo "  bash scripts/query-telemetry.sh           read the telemetry of the two apps"
echo "  bash scripts/query-logs-and-metrics.sh    read the resource logs and metrics"
echo ""
