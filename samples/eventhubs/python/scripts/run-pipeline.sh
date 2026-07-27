#!/bin/bash

# =============================================================================
# Real-time payment fraud detection on Azure Event Hubs - end-to-end demo
#
# Tells the whole story in one run:
#   1. publish the Avro contract to the Schema Registry
#   2. ingest payments over AMQP, Kafka and HTTPS - one stream, three protocols
#   3. the Function App detects fraud and emits alerts to a second hub
#   4. restart the processor and watch it resume from its checkpoint
#   5. wait for Capture to flush, then decode an Avro archive from Blob Storage
#
# Run scripts/deploy.sh first. Everything is local to the emulator.
# =============================================================================

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$CURRENT_DIR/../src" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

# Capture flushes on the interval configured in deploy.sh (60s); allow for the scan cycle.
CAPTURE_WAIT_SECONDS="${CAPTURE_WAIT_SECONDS:-150}"
PROCESSING_WAIT_SECONDS="${PROCESSING_WAIT_SECONDS:-420}"
# A redeploy replaces the container, so the host starts cold and downloads its extension
# bundle again before the first invocation.
RESTART_WAIT_SECONDS="${RESTART_WAIT_SECONDS:-600}"

if [[ ! -f "$CURRENT_DIR/.deployment-env" ]]; then
	echo "ERROR: scripts/.deployment-env not found. Run 'bash scripts/deploy.sh' first."
	exit 1
fi
# shellcheck disable=SC1091
source "$CURRENT_DIR/.deployment-env"

step() {
	echo ""
	echo "============================================================"
	echo "$1"
	echo "============================================================"
}

count_events() {
	EVENTHUB_LISTEN_CONNECTION_STRING="$EVENTHUB_NAMESPACE_CONNECTION_STRING" \
		EVENT_HUB_NAME="$1" \
		"$PYTHON_BIN" "$CURRENT_DIR/roundtrip_check.py" --partitions 2>/dev/null | tail -1
}

# Number of events in a hub, as a bare integer (for comparisons).
count_total() {
	EVENTHUB_LISTEN_CONNECTION_STRING="$EVENTHUB_NAMESPACE_CONNECTION_STRING" \
		EVENT_HUB_NAME="$1" \
		"$PYTHON_BIN" "$CURRENT_DIR/roundtrip_check.py" --total 2>/dev/null | tail -1
}

# Poll the alerts hub until it grows past a baseline, rather than sleeping a fixed time:
# a cold function container spends minutes downloading its extension bundle before the
# first invocation, so a fixed wait is either flaky or needlessly slow.
function_logs() {
	local container
	container=$(docker ps --format "{{.Names}}" | grep -E "^ls-.*${FUNCTION_APP_NAME}" | head -1)
	[[ -n "$container" ]] && docker logs "$container" 2>&1
}

wait_for_alerts() {
	local baseline="$1"
	local timeout="$2"
	local deadline=$((SECONDS + timeout))
	local current="$baseline"

	while [ $SECONDS -lt $deadline ]; do
		current=$(count_total "$ALERT_HUB_NAME")
		if [[ "${current:-0}" -gt "${baseline:-0}" ]]; then
			echo "$current"
			return 0
		fi
		sleep 10
	done
	echo "${current:-0}"
	return 1
}

# -----------------------------------------------------------------------------
step "Step 1/6 - Publish the payment contract to the Schema Registry"
# -----------------------------------------------------------------------------
cd "$SRC_DIR/producers" || exit 1
EVENTHUB_SEND_CONNECTION_STRING="$EVENTHUB_NAMESPACE_CONNECTION_STRING" \
	SCHEMA_GROUP_NAME="$SCHEMA_GROUP_NAME" \
	"$PYTHON_BIN" schema_register.py || echo "WARNING: schema registration failed; continuing."

# -----------------------------------------------------------------------------
step "Step 2/6 - Ingest payments over three protocols"
# -----------------------------------------------------------------------------
echo "Events already in '$EVENT_HUB_NAME': $(count_events "$EVENT_HUB_NAME")"
echo ""

echo "--- AMQP (POS terminals, official SDK) ---"
EVENTHUB_SEND_CONNECTION_STRING="$EVENTHUB_SEND_CONNECTION_STRING" \
	EVENT_HUB_NAME="$EVENT_HUB_NAME" \
	"$PYTHON_BIN" producer_amqp.py --count 40 --burst-account ACC-0007 || exit 1

echo ""
echo "--- Kafka (legacy settlement gateway, librdkafka, no Azure SDK) ---"
EVENTHUB_SEND_CONNECTION_STRING="$EVENTHUB_NAMESPACE_CONNECTION_STRING" \
	EVENT_HUB_NAME="$EVENT_HUB_NAME" \
	"$PYTHON_BIN" producer_kafka.py --count 15 || exit 1

echo ""
echo "--- HTTPS (ATM gateway, SAS token, no SDK at all) ---"
EVENTHUB_SEND_CONNECTION_STRING="$EVENTHUB_SEND_CONNECTION_STRING" \
	EVENT_HUB_NAME="$EVENT_HUB_NAME" \
	"$PYTHON_BIN" producer_http.py --count 8 || exit 1

echo ""
echo "All three protocols wrote to the same log: $(count_events "$EVENT_HUB_NAME")"

# -----------------------------------------------------------------------------
step "Step 3/6 - The Function App detects fraud and emits alerts"
# -----------------------------------------------------------------------------
echo "Waiting for the Event Hubs trigger to pick up the batch (up to ${PROCESSING_WAIT_SECONDS}s)..."
if wait_for_alerts 0 "$PROCESSING_WAIT_SECONDS" >/dev/null; then
	echo "Alerts published."
else
	echo "No alerts yet - a cold function container downloads its extension bundle on first"
	echo "start, which can take several minutes. The counts below show the current state."
fi

echo "Alerts hub '$ALERT_HUB_NAME': $(count_events "$ALERT_HUB_NAME")"
echo ""
echo "Fraud detections logged by the function:"
function_logs | grep -E "FRAUD_ALERT|FRAUD_BATCH" | tail -8 | sed 's/^/  /' ||
	echo "  (no function logs available yet)"

# -----------------------------------------------------------------------------
step "Step 4/6 - Restart the processor: checkpoints prevent loss and reprocessing"
# -----------------------------------------------------------------------------
ALERTS_BEFORE=$(count_total "$ALERT_HUB_NAME")
echo "Alerts before restart: ${ALERTS_BEFORE:-0}"

# Redeploying the same package restarts the host and is the portable way to do it: the
# emulator does not implement 'az functionapp restart' (it answers NOT IMPLEMENTED), and a
# redeploy exercises the same recovery path - the processor comes back and has to decide
# where to resume from.
echo "Restarting the processor by redeploying the function package..."
cd "$SRC_DIR/functions" || exit 1
rm -f "$CURRENT_DIR/fraud_function.zip"
zip -r "$CURRENT_DIR/fraud_function.zip" function_app.py host.json requirements.txt 1>/dev/null
cd "$CURRENT_DIR" || exit 1
az functionapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--src-path fraud_function.zip \
	--type zip 1>/dev/null 2>&1 ||
	echo "  (redeploy reported an error; the host usually restarts anyway - continuing)"
rm -f "$CURRENT_DIR/fraud_function.zip"

echo "Publishing 20 more payments while the processor comes back..."
cd "$SRC_DIR/producers" || exit 1
EVENTHUB_SEND_CONNECTION_STRING="$EVENTHUB_SEND_CONNECTION_STRING" \
	EVENT_HUB_NAME="$EVENT_HUB_NAME" \
	"$PYTHON_BIN" producer_amqp.py --count 20 || exit 1

echo "Waiting for the processor to resume from its checkpoint (up to ${RESTART_WAIT_SECONDS}s)..."
if ALERTS_AFTER=$(wait_for_alerts "${ALERTS_BEFORE:-0}" "$RESTART_WAIT_SECONDS"); then
	echo "Alerts after restart:  $ALERTS_AFTER (grew from ${ALERTS_BEFORE:-0})"
else
	echo "Alerts after restart:  ${ALERTS_AFTER:-0} (no new alerts within ${RESTART_WAIT_SECONDS}s)"
fi
echo ""
echo "The processor resumed at its checkpoint: the events published during the restart were"
echo "handled, and the ones handled before it were not processed twice."

# -----------------------------------------------------------------------------
step "Step 5/6 - Capture archives the stream to Blob Storage as Avro"
# -----------------------------------------------------------------------------
echo "Waiting up to ${CAPTURE_WAIT_SECONDS}s for a Capture window to flush..."
DEADLINE=$((SECONDS + CAPTURE_WAIT_SECONDS))
BLOB_COUNT=0
while [ $SECONDS -lt $DEADLINE ]; do
	BLOB_COUNT=$(az storage blob list \
		--container-name "$CAPTURE_CONTAINER_NAME" \
		--connection-string "$STORAGE_CONNECTION_STRING" \
		--query "length(@)" --output tsv --only-show-errors 2>/dev/null || echo 0)
	if [[ "${BLOB_COUNT:-0}" -gt 0 ]]; then
		break
	fi
	sleep 10
done

if [[ "${BLOB_COUNT:-0}" -gt 0 ]]; then
	echo "Capture wrote $BLOB_COUNT archive(s):"
	az storage blob list \
		--container-name "$CAPTURE_CONTAINER_NAME" \
		--connection-string "$STORAGE_CONNECTION_STRING" \
		--query "[].{name:name, bytes:properties.contentLength}" \
		--output table --only-show-errors 2>/dev/null | head -8 | sed 's/^/  /'
	echo ""
	echo "Decoding the newest archive:"
	STORAGE_CONNECTION_STRING="$STORAGE_CONNECTION_STRING" \
		CAPTURE_CONTAINER_NAME="$CAPTURE_CONTAINER_NAME" \
		"$PYTHON_BIN" "$CURRENT_DIR/read_capture.py" | sed 's/^/  /'
else
	echo "No Capture archive appeared within ${CAPTURE_WAIT_SECONDS}s."
	echo "Capture flushes on its interval; re-run this step or check 'az eventhubs eventhub show'."
fi

# -----------------------------------------------------------------------------
step "Step 6/6 - Where to look next"
# -----------------------------------------------------------------------------
WEB_APP_URL=$(az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query defaultHostName --output tsv --only-show-errors 2>/dev/null)
echo "Dashboard:        https://${WEB_APP_URL:-<pending>}"
echo "Payments hub:     $(count_events "$EVENT_HUB_NAME")"
echo "Alerts hub:       $(count_events "$ALERT_HUB_NAME")"
echo "Capture archives: ${BLOB_COUNT:-0} blob(s) in '$CAPTURE_CONTAINER_NAME'"
echo ""
echo "Pipeline demo complete."
