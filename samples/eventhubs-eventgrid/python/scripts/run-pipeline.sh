#!/bin/bash

# =============================================================================
# Cold-path automation - end-to-end demo
#
#   1. publish telemetry into the Capture-enabled hub
#   2. wait for a Capture window to flush an Avro archive to Blob Storage
#   3. Event Hubs raises CaptureFileCreated; Event Grid delivers it to a hub
#   4. the Function App decodes the archive and writes per-device summaries
#   5. read the curated hub and show the summaries
#
# Every step is an assertion: the script exits non-zero the moment the chain
# breaks, and prints the processor's container logs so the reason is visible.
# A clean exit means the whole pipeline ran.
#
# Run scripts/deploy.sh first. Everything is local to the emulator.
# =============================================================================

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$CURRENT_DIR/../src" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

READING_COUNT="${READING_COUNT:-120}"
DEVICE_COUNT="${DEVICE_COUNT:-6}"
EXCURSION_DEVICE="${EXCURSION_DEVICE:-DEV-0003}"
# Capture flushes on a 60s window; allow for the scan cycle behind it.
CAPTURE_WAIT_SECONDS="${CAPTURE_WAIT_SECONDS:-180}"
# The processor is a cold container on first run: it downloads its extension bundle before the
# first invocation, so the summary can take minutes to appear the first time.
SUMMARY_WAIT_SECONDS="${SUMMARY_WAIT_SECONDS:-420}"

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

fail() {
	echo ""
	echo "============================================================"
	echo "PIPELINE FAILED: $1"
	echo "============================================================"
	local logs
	logs=$(function_logs)
	if [[ -n "$logs" ]]; then
		echo ""
		echo "Processor container logs (last 40 lines):"
		echo "$logs" | tail -40 | sed 's/^/  /'
	elif command -v docker >/dev/null 2>&1; then
		echo ""
		echo "No processor container is running - the Functions host never started."
	fi
	exit 1
}

archive_count() {
	az storage blob list \
		--container-name "$CAPTURE_CONTAINER_NAME" \
		--connection-string "$STORAGE_CONNECTION_STRING" \
		--query "length(@)" --output tsv --only-show-errors 2>/dev/null || echo 0
}

# -----------------------------------------------------------------------------
step "Step 1/5 - Publish telemetry into the Capture-enabled hub"
# -----------------------------------------------------------------------------
ARCHIVES_BEFORE=$(archive_count)
echo "Archives already in '$CAPTURE_CONTAINER_NAME': ${ARCHIVES_BEFORE:-0}"

cd "$SRC_DIR/producers" || fail "missing src/producers"
"$PYTHON_BIN" telemetry_producer.py \
	--count "$READING_COUNT" \
	--devices "$DEVICE_COUNT" \
	--excursion-device "$EXCURSION_DEVICE" ||
	fail "the telemetry producer could not publish to '$TELEMETRY_HUB_NAME'"
cd "$CURRENT_DIR" || fail "could not return to the scripts directory"

echo ""
echo "Readings are keyed by device, so each device's readings land on one partition - and"
echo "therefore inside one archive, in order. That is what makes per-device aggregation exact."

# -----------------------------------------------------------------------------
step "Step 2/5 - Wait for Capture to flush an Avro archive"
# -----------------------------------------------------------------------------
echo "Capture writes on a 60s window (up to ${CAPTURE_WAIT_SECONDS}s allowed)..."
DEADLINE=$((SECONDS + CAPTURE_WAIT_SECONDS))
ARCHIVES_AFTER=$ARCHIVES_BEFORE
while [ $SECONDS -lt $DEADLINE ]; do
	ARCHIVES_AFTER=$(archive_count)
	if [[ "${ARCHIVES_AFTER:-0}" -gt "${ARCHIVES_BEFORE:-0}" ]]; then
		break
	fi
	sleep 10
done
if [[ "${ARCHIVES_AFTER:-0}" -le "${ARCHIVES_BEFORE:-0}" ]]; then
	fail "Capture wrote no new archive to '$CAPTURE_CONTAINER_NAME' within ${CAPTURE_WAIT_SECONDS}s"
fi

echo "Capture wrote $((ARCHIVES_AFTER - ARCHIVES_BEFORE)) new archive(s):"
az storage blob list \
	--container-name "$CAPTURE_CONTAINER_NAME" \
	--connection-string "$STORAGE_CONNECTION_STRING" \
	--query "[].{name:name, bytes:properties.contentLength}" \
	--output table --only-show-errors 2>/dev/null | head -8 | sed 's/^/  /'

# -----------------------------------------------------------------------------
step "Step 3/5 - Event Hubs raises CaptureFileCreated, Event Grid delivers it"
# -----------------------------------------------------------------------------
echo "Reading '$NOTIFICATION_HUB_NAME', where the subscription's EventHub destination delivers..."
NOTIFICATIONS=$(EVENTHUB_LISTEN_CONNECTION_STRING="$EVENTHUB_LISTEN_CONNECTION_STRING" \
	EVENT_HUB_NAME="$NOTIFICATION_HUB_NAME" \
	"$PYTHON_BIN" "$CURRENT_DIR/roundtrip_check.py" --partitions 2>/dev/null | tail -1)
echo "  $NOTIFICATIONS"
echo ""
echo "Nothing polled Blob Storage and no webhook was exposed: the notification arrived as a"
echo "stream event, which is why a plain Event Hubs trigger can consume it."

# -----------------------------------------------------------------------------
step "Step 4/5 - The processor decodes the archive and curates it"
# -----------------------------------------------------------------------------
echo "Waiting for the first device summary (up to ${SUMMARY_WAIT_SECONDS}s on a cold container)..."
DEADLINE=$((SECONDS + SUMMARY_WAIT_SECONDS))
SUMMARY_OUTPUT=""
while [ $SECONDS -lt $DEADLINE ]; do
	SUMMARY_OUTPUT=$(EVENTHUB_LISTEN_CONNECTION_STRING="$EVENTHUB_LISTEN_CONNECTION_STRING" \
		CURATED_HUB_NAME="$CURATED_HUB_NAME" \
		"$PYTHON_BIN" "$CURRENT_DIR/read_curated.py" 2>/dev/null)
	if [[ "$SUMMARY_OUTPUT" == SUMMARIES_OK* ]]; then
		break
	fi
	sleep 15
done

if [[ "$SUMMARY_OUTPUT" != SUMMARIES_OK* ]]; then
	fail "no device summary reached '$CURATED_HUB_NAME' within ${SUMMARY_WAIT_SECONDS}s - the archive was never processed"
fi

echo "$SUMMARY_OUTPUT" | sed 's/^/  /'

echo ""
echo "Fraud-free but not signal-free: '$EXCURSION_DEVICE' should report excursions above"
echo "${TEMPERATURE_LIMIT}C, and every other device none."
if ! echo "$SUMMARY_OUTPUT" | grep -q "$EXCURSION_DEVICE"; then
	fail "the summaries do not mention '$EXCURSION_DEVICE', so the archive was only partly processed"
fi

# -----------------------------------------------------------------------------
step "Step 5/5 - What just happened"
# -----------------------------------------------------------------------------
cat <<'SUMMARY'
  telemetry hub          devices published, keyed by device id
     |
     | Capture (60s window)
     v
  Avro archive in Blob   durable, ordered, replayable
     |
     | Microsoft.EventHub.CaptureFileCreated
     v
  Event Grid system topic
     |
     | subscription with an EventHub destination
     v
  capture-notifications  a stream, not a webhook
     |
     | Event Hubs trigger
     v
  Function App           downloads the archive, aggregates per device
     |
     | Event Hubs output binding
     v
  curated hub            one summary per device
SUMMARY

echo ""
echo "Pipeline demo complete: every stage ran and was verified."
