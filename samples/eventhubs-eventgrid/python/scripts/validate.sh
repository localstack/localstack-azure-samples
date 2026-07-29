#!/bin/bash

# =============================================================================
# Verifies every capability the cold-path pipeline deploys, in the order an
# operator would check them: Event Hubs, then Capture, then the Event Grid
# wiring that connects them, then the workloads and the data plane.
# =============================================================================

PREFIX='local'
SUFFIX='telemetry'
RESOURCE_GROUP_NAME="${PREFIX}-ehgrid-rg"
EVENTHUB_NAMESPACE_NAME="${PREFIX}-ehns-${SUFFIX}"
TELEMETRY_HUB_NAME='telemetry'
NOTIFICATION_HUB_NAME='capture-notifications'
CURATED_HUB_NAME='curated'
CAPTURE_CONTAINER_NAME='telemetry-archive'
CAPTURE_CONSUMER_GROUP='capture-processor'
STORAGE_ACCOUNT_NAME="${PREFIX}ehgrid${SUFFIX:0:4}"
SYSTEM_TOPIC_NAME="${PREFIX}-ehns-systopic"
SUBSCRIPTION_NAME='capture-to-eventhub'
FUNCTION_APP_NAME="${PREFIX}-ehgrid-processor"
SEND_RULE_NAME='telemetry-send'
LISTEN_RULE_NAME='pipeline-listen'
TELEMETRY_PARTITION_COUNT=4

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

PASS_COUNT=0
FAIL_COUNT=0

check() {
	local description="$1"
	local command="$2"
	echo -n "  Checking $description... "
	if eval "$command" &>/dev/null; then
		echo "OK"
		PASS_COUNT=$((PASS_COUNT + 1))
	else
		echo "FAIL"
		FAIL_COUNT=$((FAIL_COUNT + 1))
	fi
}

check_output() {
	local description="$1"
	local command="$2"
	local expected="$3"
	echo -n "  Checking $description... "
	local output
	output=$(eval "$command" 2>/dev/null)
	if echo "$output" | grep -q "$expected"; then
		echo "OK"
		PASS_COUNT=$((PASS_COUNT + 1))
	else
		echo "FAIL (expected '$expected', got '$(echo "$output" | head -1)')"
		FAIL_COUNT=$((FAIL_COUNT + 1))
	fi
}

echo "============================================================"
echo "Validating the Capture -> Event Grid -> Functions pipeline"
echo "============================================================"

echo ""
echo "--- Part 1: Event Hubs ---"
echo ""

echo "[1] Namespace and hubs"
check "resource group exists" \
	"az group show --name $RESOURCE_GROUP_NAME"
check "Event Hubs namespace exists" \
	"az eventhubs namespace show --name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME"
check_output "namespace is Standard tier (Capture requires it)" \
	"az eventhubs namespace show --name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query sku.name -o tsv" \
	"Standard"
for hub in "$TELEMETRY_HUB_NAME" "$NOTIFICATION_HUB_NAME" "$CURATED_HUB_NAME"; do
	check "hub '$hub' exists" \
		"az eventhubs eventhub show --name $hub --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME"
done
check_output "telemetry hub has $TELEMETRY_PARTITION_COUNT partitions" \
	"az eventhubs eventhub show --name $TELEMETRY_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query partitionCount -o tsv" \
	"^${TELEMETRY_PARTITION_COUNT}$"
echo ""

echo "[2] Capture configuration"
check_output "Capture is enabled on the telemetry hub" \
	"az eventhubs eventhub show --name $TELEMETRY_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query captureDescription.enabled -o tsv" \
	"true"
check_output "Capture encoding is Avro" \
	"az eventhubs eventhub show --name $TELEMETRY_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query captureDescription.encoding -o tsv" \
	"Avro"
check_output "Capture targets the archive container" \
	"az eventhubs eventhub show --name $TELEMETRY_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query captureDescription.destination.blobContainer -o tsv" \
	"$CAPTURE_CONTAINER_NAME"
check "consumer group '$CAPTURE_CONSUMER_GROUP' exists on the notifications hub" \
	"az eventhubs eventhub consumer-group show --consumer-group-name $CAPTURE_CONSUMER_GROUP --eventhub-name $NOTIFICATION_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

echo "[3] Authorization rules (least privilege)"
check_output "telemetry send rule grants only Send" \
	"az eventhubs eventhub authorization-rule show --name $SEND_RULE_NAME --eventhub-name $TELEMETRY_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query \"join(',', rights)\" -o tsv" \
	"^Send$"
check_output "pipeline listen rule grants only Listen" \
	"az eventhubs namespace authorization-rule show --name $LISTEN_RULE_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query \"join(',', rights)\" -o tsv" \
	"^Listen$"
echo ""

echo "--- Part 2: Event Grid wiring ---"
echo ""

echo "[4] System topic over the namespace"
check "system topic exists" \
	"az eventgrid system-topic show --name $SYSTEM_TOPIC_NAME --resource-group $RESOURCE_GROUP_NAME"
check_output "system topic is an Event Hubs namespace topic type" \
	"az eventgrid system-topic show --name $SYSTEM_TOPIC_NAME --resource-group $RESOURCE_GROUP_NAME --query topicType -o tsv" \
	"[Ee]venthub"
check_output "system topic sources the Event Hubs namespace" \
	"az eventgrid system-topic show --name $SYSTEM_TOPIC_NAME --resource-group $RESOURCE_GROUP_NAME --query source -o tsv" \
	"$EVENTHUB_NAMESPACE_NAME"
echo ""

echo "[5] Event subscription delivering to an event hub"
check "event subscription exists" \
	"az eventgrid system-topic event-subscription show --name $SUBSCRIPTION_NAME --system-topic-name $SYSTEM_TOPIC_NAME --resource-group $RESOURCE_GROUP_NAME"
check_output "its destination is an EventHub endpoint" \
	"az eventgrid system-topic event-subscription show --name $SUBSCRIPTION_NAME --system-topic-name $SYSTEM_TOPIC_NAME --resource-group $RESOURCE_GROUP_NAME --query destination.endpointType -o tsv" \
	"EventHub"
echo ""

echo "--- Part 3: Workloads and data plane ---"
echo ""

echo "[6] Function App"
check "function app exists" \
	"az functionapp show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME"
check_output "it is configured with the notifications hub" \
	"az functionapp config appsettings list --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query \"[?name=='NOTIFICATION_HUB_NAME'].value\" -o tsv" \
	"$NOTIFICATION_HUB_NAME"
check_output "it is configured with the curated hub" \
	"az functionapp config appsettings list --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query \"[?name=='CURATED_HUB_NAME'].value\" -o tsv" \
	"$CURATED_HUB_NAME"
echo ""

echo "[7] Storage"
check "storage account exists" \
	"az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

echo "[8] Data plane round trip"
echo -n "  Checking the telemetry hub accepts and returns an event... "
ROUNDTRIP=$(EVENTHUB_SEND_CONNECTION_STRING=$(az eventhubs eventhub authorization-rule keys list \
	--name "$SEND_RULE_NAME" --eventhub-name "$TELEMETRY_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryConnectionString -o tsv --only-show-errors) \
	EVENTHUB_LISTEN_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
		--name "$LISTEN_RULE_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query primaryConnectionString -o tsv --only-show-errors) \
	EVENT_HUB_NAME="$TELEMETRY_HUB_NAME" \
	"$PYTHON_BIN" "$CURRENT_DIR/roundtrip_check.py" 2>&1 | tail -1)
if [[ "$ROUNDTRIP" == ROUNDTRIP_OK* ]]; then
	echo "OK (${ROUNDTRIP#ROUNDTRIP_OK })"
	PASS_COUNT=$((PASS_COUNT + 1))
else
	echo "FAIL ($ROUNDTRIP)"
	FAIL_COUNT=$((FAIL_COUNT + 1))
fi
echo ""

echo "============================================================"
echo "Validation results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "============================================================"

if [ $FAIL_COUNT -eq 0 ]; then
	echo "PASS: the pipeline is deployed and every capability responded."
	exit 0
else
	echo "FAIL: review the output above."
	exit 1
fi
