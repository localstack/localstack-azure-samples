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
# Every step is an assertion, not a narration: the script exits non-zero the
# moment the pipeline stops behaving, and prints the function container's logs
# so the reason is in the output. A clean exit means the whole pipeline ran.
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

# How many payments each protocol publishes, and the total the payments hub must grow by.
# --burst-account makes producer_amqp.py add a fixed card-testing burst on top of --count.
AMQP_COUNT=40
AMQP_BURST_COUNT=12
KAFKA_COUNT=15
HTTP_COUNT=8
RESTART_COUNT=20
EXPECTED_INGEST=$((AMQP_COUNT + AMQP_BURST_COUNT + KAFKA_COUNT + HTTP_COUNT))
# Accounts used for the two card-testing bursts. Step 4 uses a different one from step 2 so
# the alert it waits for can only have come from the payments published after the restart.
INGEST_BURST_ACCOUNT='ACC-0007'
RESTART_BURST_ACCOUNT='ACC-0042'

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

function_logs() {
	command -v docker >/dev/null 2>&1 || return 1
	local container
	container=$(docker ps --format "{{.Names}}" | grep -E "^ls-.*${FUNCTION_APP_NAME}" | head -1)
	[[ -n "$container" ]] && docker logs "$container" 2>&1
}

# Print whatever the function host has to say, then stop. The logs are the only place the
# reason for a silent processor shows up, so they are always dumped on the way out.
fail() {
	echo ""
	echo "============================================================"
	echo "PIPELINE FAILED: $1"
	echo "============================================================"
	local logs
	logs=$(function_logs)
	if [[ -n "$logs" ]]; then
		echo ""
		echo "Function App container logs (last 40 lines):"
		echo "$logs" | tail -40 | sed 's/^/  /'
	elif command -v docker >/dev/null 2>&1; then
		echo ""
		echo "No Function App container is running - the host never started."
	fi
	exit 1
}

count_events() {
	EVENTHUB_LISTEN_CONNECTION_STRING="$EVENTHUB_NAMESPACE_CONNECTION_STRING" \
		EVENT_HUB_NAME="$1" \
		"$PYTHON_BIN" "$CURRENT_DIR/roundtrip_check.py" --partitions 2>/dev/null | tail -1
}

# Number of events in a hub, as a bare integer. Returns non-zero when the hub cannot be
# read at all, so a broken data plane is never mistaken for an empty hub.
count_total() {
	local total
	total=$(EVENTHUB_LISTEN_CONNECTION_STRING="$EVENTHUB_NAMESPACE_CONNECTION_STRING" \
		EVENT_HUB_NAME="$1" \
		"$PYTHON_BIN" "$CURRENT_DIR/roundtrip_check.py" --total 2>/dev/null | tail -1)
	[[ "$total" =~ ^[0-9]+$ ]] || return 1
	echo "$total"
}

# Poll the alerts hub until it grows past a baseline, rather than sleeping a fixed time:
# a cold function container spends minutes downloading its extension bundle before the
# first invocation, so a fixed wait is either flaky or needlessly slow.
wait_for_alerts() {
	local baseline="$1"
	local timeout="$2"
	local deadline=$((SECONDS + timeout))
	local current="$baseline"

	while [ $SECONDS -lt $deadline ]; do
		current=$(count_total "$ALERT_HUB_NAME") || current="$baseline"
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
cd "$SRC_DIR/producers" || fail "missing src/producers"
EVENTHUB_SEND_CONNECTION_STRING="$EVENTHUB_NAMESPACE_CONNECTION_STRING" \
	SCHEMA_GROUP_NAME="$SCHEMA_GROUP_NAME" \
	"$PYTHON_BIN" schema_register.py || fail "the Avro contract could not be registered in the Schema Registry"

# -----------------------------------------------------------------------------
step "Step 2/6 - Ingest payments over three protocols"
# -----------------------------------------------------------------------------
PAYMENTS_BEFORE=$(count_total "$EVENT_HUB_NAME") ||
	fail "the payments hub '$EVENT_HUB_NAME' could not be read"
# Baseline the alerts hub before publishing anything. Re-running against a deployment that
# already produced alerts must still prove that *these* payments were processed, so step 3
# waits for growth past this mark rather than for the hub to be non-empty.
ALERTS_BASELINE=$(count_total "$ALERT_HUB_NAME") ||
	fail "the alerts hub '$ALERT_HUB_NAME' could not be read"
echo "Events already in '$EVENT_HUB_NAME': $(count_events "$EVENT_HUB_NAME")"
echo ""

echo "--- AMQP (POS terminals, official SDK) ---"
EVENTHUB_SEND_CONNECTION_STRING="$EVENTHUB_SEND_CONNECTION_STRING" \
	EVENT_HUB_NAME="$EVENT_HUB_NAME" \
	"$PYTHON_BIN" producer_amqp.py --count "$AMQP_COUNT" --burst-account "$INGEST_BURST_ACCOUNT" ||
	fail "the AMQP producer could not publish to '$EVENT_HUB_NAME'"

echo ""
echo "--- Kafka (legacy settlement gateway, librdkafka, no Azure SDK) ---"
EVENTHUB_SEND_CONNECTION_STRING="$EVENTHUB_NAMESPACE_CONNECTION_STRING" \
	EVENT_HUB_NAME="$EVENT_HUB_NAME" \
	"$PYTHON_BIN" producer_kafka.py --count "$KAFKA_COUNT" ||
	fail "the Kafka producer could not publish to '$EVENT_HUB_NAME'"

echo ""
echo "--- HTTPS (ATM gateway, SAS token, no SDK at all) ---"
EVENTHUB_SEND_CONNECTION_STRING="$EVENTHUB_SEND_CONNECTION_STRING" \
	EVENT_HUB_NAME="$EVENT_HUB_NAME" \
	"$PYTHON_BIN" producer_http.py --count "$HTTP_COUNT" ||
	fail "the HTTPS producer could not publish to '$EVENT_HUB_NAME'"

# The point of this step is that three protocols share one log, so count the log rather
# than trusting three exit codes: a producer that reports success but writes nowhere,
# or writes into a different partition set, is caught here.
PAYMENTS_AFTER=$(count_total "$EVENT_HUB_NAME") ||
	fail "the payments hub '$EVENT_HUB_NAME' could not be read after ingestion"
INGESTED=$((PAYMENTS_AFTER - PAYMENTS_BEFORE))
if [[ "$INGESTED" -lt "$EXPECTED_INGEST" ]]; then
	fail "only $INGESTED of $EXPECTED_INGEST published payments reached '$EVENT_HUB_NAME' (AMQP $AMQP_COUNT + burst $AMQP_BURST_COUNT + Kafka $KAFKA_COUNT + HTTPS $HTTP_COUNT)"
fi

echo ""
echo "All three protocols wrote to the same log: $(count_events "$EVENT_HUB_NAME")"
echo "The log grew by $INGESTED events, covering the $EXPECTED_INGEST payments published"
echo "(AMQP $AMQP_COUNT + burst $AMQP_BURST_COUNT, Kafka $KAFKA_COUNT, HTTPS $HTTP_COUNT)."

# -----------------------------------------------------------------------------
step "Step 3/6 - The Function App detects fraud and emits alerts"
# -----------------------------------------------------------------------------
echo "Waiting for the Event Hubs trigger to pick up the batch (up to ${PROCESSING_WAIT_SECONDS}s)..."
wait_for_alerts "$ALERTS_BASELINE" "$PROCESSING_WAIT_SECONDS" >/dev/null ||
	fail "no new fraud alert reached '$ALERT_HUB_NAME' within ${PROCESSING_WAIT_SECONDS}s (it held $ALERTS_BASELINE before this run) - the Event Hubs trigger is not processing the stream"
echo "Alerts published."

echo "Alerts hub '$ALERT_HUB_NAME': $(count_events "$ALERT_HUB_NAME")"
echo ""
echo "Fraud detections logged by the function:"
function_logs | grep -E "FRAUD_ALERT|FRAUD_BATCH" | tail -8 | sed 's/^/  /' ||
	echo "  (container logs are unavailable; the alerts hub above is the authoritative check)"

# -----------------------------------------------------------------------------
step "Step 4/6 - Restart the processor: checkpoints prevent loss and reprocessing"
# -----------------------------------------------------------------------------
ALERTS_BEFORE=$(count_total "$ALERT_HUB_NAME") ||
	fail "the alerts hub '$ALERT_HUB_NAME' could not be read"
echo "Alerts before restart: $ALERTS_BEFORE"

# Redeploying the same package restarts the host and is the portable way to do it: the
# emulator does not implement 'az functionapp restart' (it answers NOT IMPLEMENTED), and a
# redeploy exercises the same recovery path - the processor comes back and has to decide
# where to resume from.
echo "Restarting the processor by redeploying the function package..."
cd "$SRC_DIR/functions" || fail "missing src/functions"
rm -f "$CURRENT_DIR/fraud_function.zip"
zip -r "$CURRENT_DIR/fraud_function.zip" function_app.py host.json requirements.txt 1>/dev/null
cd "$CURRENT_DIR" || fail "could not return to the scripts directory"
az functionapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--src-path fraud_function.zip \
	--type zip 1>/dev/null ||
	fail "the function package could not be redeployed, so the restart never happened"
rm -f "$CURRENT_DIR/fraud_function.zip"

echo "Publishing $RESTART_COUNT more payments while the processor comes back..."
cd "$SRC_DIR/producers" || fail "missing src/producers"
# The burst is what makes this step a test rather than a coin flip: random payments are
# usually all legitimate, so without a guaranteed card-testing pattern the resumed
# processor would have nothing to flag and "no alerts" could mean either a broken
# processor or an honest batch. The burst removes that ambiguity.
EVENTHUB_SEND_CONNECTION_STRING="$EVENTHUB_SEND_CONNECTION_STRING" \
	EVENT_HUB_NAME="$EVENT_HUB_NAME" \
	"$PYTHON_BIN" producer_amqp.py --count "$RESTART_COUNT" --burst-account "$RESTART_BURST_ACCOUNT" ||
	fail "the AMQP producer could not publish during the restart"

echo "Waiting for the processor to resume from its checkpoint (up to ${RESTART_WAIT_SECONDS}s)..."
ALERTS_AFTER=$(wait_for_alerts "$ALERTS_BEFORE" "$RESTART_WAIT_SECONDS") ||
	fail "the processor produced no alert within ${RESTART_WAIT_SECONDS}s of the restart - it did not resume from its checkpoint"
echo "Alerts after restart:  $ALERTS_AFTER (grew from $ALERTS_BEFORE)"

# Resuming at the checkpoint means the payments handled before the restart are not handled
# again. A processor that restarted from the beginning of the log would re-emit roughly the
# whole backlog on top of the new alerts, so the count separates the two cases: resuming
# yields at most the burst's worth of alerts, replaying yields that plus the backlog again.
# The bar sits at 1.5x the backlog so neither case lands near it, and it only applies once
# the backlog is big enough for the comparison to mean anything.
NEW_ALERTS=$((ALERTS_AFTER - ALERTS_BEFORE))
if [[ "$ALERTS_BEFORE" -ge 10 && $((NEW_ALERTS * 2)) -ge $((ALERTS_BEFORE * 3)) ]]; then
	fail "the processor emitted $NEW_ALERTS alerts after the restart against a backlog of $ALERTS_BEFORE - it replayed the stream instead of resuming from its checkpoint"
fi

echo ""
echo "The processor resumed at its checkpoint: the events published during the restart were"
echo "handled ($NEW_ALERTS new alert(s)), and the ones handled before it were not processed twice."

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

if [[ "${BLOB_COUNT:-0}" -le 0 ]]; then
	fail "Capture wrote no archive to '$CAPTURE_CONTAINER_NAME' within ${CAPTURE_WAIT_SECONDS}s"
fi

echo "Capture wrote $BLOB_COUNT archive(s):"
az storage blob list \
	--container-name "$CAPTURE_CONTAINER_NAME" \
	--connection-string "$STORAGE_CONNECTION_STRING" \
	--query "[].{name:name, bytes:properties.contentLength}" \
	--output table --only-show-errors 2>/dev/null | head -8 | sed 's/^/  /'
echo ""
echo "Decoding the newest archive:"
# An archive that exists but does not decode is a Capture failure, not a success. The
# output is captured first because a pipeline reports the exit status of its last command,
# which would hide a decoder that failed.
DECODED=$(STORAGE_CONNECTION_STRING="$STORAGE_CONNECTION_STRING" \
	CAPTURE_CONTAINER_NAME="$CAPTURE_CONTAINER_NAME" \
	"$PYTHON_BIN" "$CURRENT_DIR/read_capture.py" 2>&1) ||
	fail "the newest Capture archive could not be decoded as Avro: $(echo "$DECODED" | tail -3)"
echo "$DECODED" | sed 's/^/  /'

# -----------------------------------------------------------------------------
step "Step 6/6 - Where to look next"
# -----------------------------------------------------------------------------
WEB_APP_URL=$(az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query defaultHostName --output tsv --only-show-errors 2>/dev/null)
[[ -n "$WEB_APP_URL" ]] || fail "the dashboard web app '$WEB_APP_NAME' is not readable"
echo "Dashboard:        https://${WEB_APP_URL}"
echo "Payments hub:     $(count_events "$EVENT_HUB_NAME")"
echo "Alerts hub:       $(count_events "$ALERT_HUB_NAME")"
echo "Capture archives: ${BLOB_COUNT} blob(s) in '$CAPTURE_CONTAINER_NAME'"
echo ""
echo "Pipeline demo complete: every stage ran and was verified."
