#!/bin/bash

# =============================================================================
# Real-time payment fraud detection on Azure Event Hubs - validation
#
# Verifies every capability the sample deploys, in the order an operator would
# check them: control plane first, then the data plane, then the workloads.
# Bonus checks at the end exercise geo-disaster-recovery pairing and application
# group throttling policies.
# =============================================================================

# Variables (must match deploy.sh)
PREFIX='local'
SUFFIX='payments'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-eventhubs-rg"
EVENTHUB_NAMESPACE_NAME="${PREFIX}-ehns-${SUFFIX}"
EVENT_HUB_NAME='payments'
ALERT_HUB_NAME='fraud-alerts'
FRAUD_CONSUMER_GROUP='fraud-detector'
ANALYTICS_CONSUMER_GROUP='analytics'
AUDIT_CONSUMER_GROUP='audit'
SEND_RULE_NAME='payments-send'
LISTEN_RULE_NAME='payments-listen'
SCHEMA_GROUP_NAME='payments-schemas'
STORAGE_ACCOUNT_NAME="${PREFIX}ehstorage${SUFFIX:0:4}"
CAPTURE_CONTAINER_NAME='payments-archive'
KEY_VAULT_NAME="${PREFIX}ehkv${SUFFIX:0:4}"
FUNCTION_APP_NAME="${PREFIX}-eh-fraud-func"
WEB_APP_NAME="${PREFIX}-eh-dashboard"
PARTITION_COUNT=4

# Bonus resources, created and removed by this script
DR_LOCATION="${DR_LOCATION:-northeurope}"
DR_NAMESPACE_NAME="${PREFIX}-ehns-${SUFFIX}-dr"
DR_ALIAS_NAME="${PREFIX}-payments-alias"
APPLICATION_GROUP_NAME='pos-terminals'

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

pass() {
	echo "OK ($1)"
	PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
	echo "FAIL ($1)"
	FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "============================================================"
echo "Validating the payment fraud detection pipeline"
echo "============================================================"

# =============================================================================
echo ""
echo "--- Part 1: Control plane ---"
echo ""
# =============================================================================

echo "[1] Resource group and namespace"
check "resource group exists" \
	"az group show --name $RESOURCE_GROUP_NAME"
check "Event Hubs namespace exists" \
	"az eventhubs namespace show --name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME"
check_output "namespace is Standard tier" \
	"az eventhubs namespace show --name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query sku.name -o tsv" \
	"Standard"
check_output "Kafka is enabled on the namespace" \
	"az eventhubs namespace show --name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query kafkaEnabled -o tsv" \
	"true"
check_output "auto-inflate is enabled" \
	"az eventhubs namespace show --name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query isAutoInflateEnabled -o tsv" \
	"true"
echo ""

echo "[2] Event hubs and partitions"
check "payments hub exists" \
	"az eventhubs eventhub show --name $EVENT_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME"
check_output "payments hub has $PARTITION_COUNT partitions" \
	"az eventhubs eventhub show --name $EVENT_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query partitionCount -o tsv" \
	"^${PARTITION_COUNT}$"
check "fraud-alerts hub exists" \
	"az eventhubs eventhub show --name $ALERT_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

echo "[3] Capture configuration"
check_output "Capture is enabled on the payments hub" \
	"az eventhubs eventhub show --name $EVENT_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query captureDescription.enabled -o tsv" \
	"true"
check_output "Capture encoding is Avro" \
	"az eventhubs eventhub show --name $EVENT_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query captureDescription.encoding -o tsv" \
	"Avro"
check_output "Capture targets the archive container" \
	"az eventhubs eventhub show --name $EVENT_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query captureDescription.destination.blobContainer -o tsv" \
	"$CAPTURE_CONTAINER_NAME"
echo ""

echo "[4] Consumer groups"
for consumer_group in "$FRAUD_CONSUMER_GROUP" "$ANALYTICS_CONSUMER_GROUP" "$AUDIT_CONSUMER_GROUP"; do
	check "consumer group '$consumer_group' exists" \
		"az eventhubs eventhub consumer-group show --consumer-group-name $consumer_group --eventhub-name $EVENT_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME"
done
check_output "the default consumer group is present" \
	"az eventhubs eventhub consumer-group list --eventhub-name $EVENT_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query '[].name' -o tsv" \
	'\$Default'
echo ""

echo "[5] Authorization rules (least privilege)"
check_output "send rule grants only Send" \
	"az eventhubs eventhub authorization-rule show --name $SEND_RULE_NAME --eventhub-name $EVENT_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query \"join(',', rights)\" -o tsv" \
	"^Send$"
check_output "listen rule grants only Listen" \
	"az eventhubs eventhub authorization-rule show --name $LISTEN_RULE_NAME --eventhub-name $EVENT_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query \"join(',', rights)\" -o tsv" \
	"^Listen$"
check_output "send rule issues a usable connection string" \
	"az eventhubs eventhub authorization-rule keys list --name $SEND_RULE_NAME --eventhub-name $EVENT_HUB_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query primaryConnectionString -o tsv" \
	"SharedAccessKey="
echo ""

echo "[6] Schema Registry, Key Vault, Storage"
check "schema group exists" \
	"az eventhubs namespace schema-registry show --name $SCHEMA_GROUP_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME"
check "storage account exists" \
	"az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME"
check "key vault exists" \
	"az keyvault show --name $KEY_VAULT_NAME --resource-group $RESOURCE_GROUP_NAME"
for secret in eventhub-send-connection eventhub-listen-connection storage-connection; do
	check "secret '$secret' is stored" \
		"az keyvault secret show --vault-name $KEY_VAULT_NAME --name $secret"
done
echo ""

echo "[7] Workloads"
check "function app exists" \
	"az functionapp show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME"
check "web app exists" \
	"az webapp show --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

# =============================================================================
echo "--- Part 2: Data plane ---"
echo ""
# =============================================================================

SEND_CONNECTION=$(az eventhubs eventhub authorization-rule keys list \
	--name "$SEND_RULE_NAME" --eventhub-name "$EVENT_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryConnectionString --output tsv --only-show-errors 2>/dev/null)
LISTEN_CONNECTION=$(az eventhubs eventhub authorization-rule keys list \
	--name "$LISTEN_RULE_NAME" --eventhub-name "$EVENT_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryConnectionString --output tsv --only-show-errors 2>/dev/null)

echo "[8] AMQP round trip (send with the send rule, read with the listen rule)"
echo -n "  Checking an event survives a send/receive round trip... "
ROUNDTRIP=$(EVENTHUB_SEND_CONNECTION_STRING="$SEND_CONNECTION" \
	EVENTHUB_LISTEN_CONNECTION_STRING="$LISTEN_CONNECTION" \
	EVENT_HUB_NAME="$EVENT_HUB_NAME" \
	"$PYTHON_BIN" "$CURRENT_DIR/roundtrip_check.py" 2>&1 | tail -1)
if [[ "$ROUNDTRIP" == ROUNDTRIP_OK* ]]; then
	pass "${ROUNDTRIP#ROUNDTRIP_OK }"
else
	fail "$ROUNDTRIP"
fi
echo ""

echo "[9] Runtime information"
echo -n "  Checking partition runtime metadata is readable... "
PARTITIONS=$(EVENTHUB_LISTEN_CONNECTION_STRING="$LISTEN_CONNECTION" \
	EVENT_HUB_NAME="$EVENT_HUB_NAME" \
	"$PYTHON_BIN" "$CURRENT_DIR/roundtrip_check.py" --partitions 2>&1 | tail -1)
if [[ "$PARTITIONS" == PARTITIONS_OK* ]]; then
	pass "${PARTITIONS#PARTITIONS_OK }"
else
	fail "$PARTITIONS"
fi
echo ""

# =============================================================================
echo "--- Part 3: Bonus capabilities ---"
echo ""
# =============================================================================

echo "[10] Application group with a throttling policy"
# Emulator-only: real Azure offers application groups on the Premium and Dedicated tiers
# only, so this check cannot pass against the Standard namespace this sample deploys.
# Bumping the tier for one bonus check is not worth it, so the deviation is documented.
# https://learn.microsoft.com/en-us/azure/event-hubs/resource-governance-overview
# The identifier names a namespace-level SAS key, which is what the property expects.
if az eventhubs namespace application-group create \
	--name "$APPLICATION_GROUP_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--client-app-group-identifier "NamespaceSASKeyName=RootManageSharedAccessKey" \
	--is-enabled true \
	--throttling-policy-config name=limit-ingress metric-id=IncomingMessages rate-limit-threshold=10000 \
	--only-show-errors &>/dev/null; then
	pass "created with a ThrottlingPolicy"
else
	fail "could not create the application group"
fi
check_output "the throttling policy is readable" \
	"az eventhubs namespace application-group show --name $APPLICATION_GROUP_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query 'policies[0].type' -o tsv" \
	"ThrottlingPolicy"
az eventhubs namespace application-group delete \
	--name "$APPLICATION_GROUP_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null
echo ""

echo "[11] Geo-disaster recovery pairing"
echo -n "  Creating the secondary namespace... "
# Real Azure pairs namespaces across regions - the documented setup puts the secondary in a
# different region from the primary - so the sample does the same. Regions are nominal on
# the emulator, which is why a distinct DR region costs nothing here.
# https://learn.microsoft.com/en-us/azure/event-hubs/configure-geo-disaster-recovery
if az eventhubs namespace create \
	--name "$DR_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--location "$DR_LOCATION" --sku Standard --only-show-errors &>/dev/null; then
	pass "secondary namespace created"
else
	fail "could not create the secondary namespace"
fi

DR_NAMESPACE_ID=$(az eventhubs namespace show --name "$DR_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query id --output tsv --only-show-errors 2>/dev/null)

echo -n "  Pairing the namespaces behind an alias... "
if az eventhubs georecovery-alias create \
	--alias "$DR_ALIAS_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--partner-namespace "$DR_NAMESPACE_ID" \
	--only-show-errors &>/dev/null; then
	pass "alias '$DR_ALIAS_NAME' created"
else
	fail "could not create the geo-recovery alias"
fi

check_output "the alias reports its pairing role" \
	"az eventhubs georecovery-alias show --alias $DR_ALIAS_NAME --namespace-name $EVENTHUB_NAMESPACE_NAME --resource-group $RESOURCE_GROUP_NAME --query role -o tsv" \
	"Primary"

# Break the pairing and remove the secondary so the sample leaves no extra resources.
az eventhubs georecovery-alias break-pair --alias "$DR_ALIAS_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null
az eventhubs georecovery-alias delete --alias "$DR_ALIAS_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors &>/dev/null
az eventhubs namespace delete --name "$DR_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --only-show-errors &>/dev/null &
echo ""

# =============================================================================
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
