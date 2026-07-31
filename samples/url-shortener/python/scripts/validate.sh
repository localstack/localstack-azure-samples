#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}msastorage${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-msa-log-analytics-${SUFFIX}"
WEB_APP_NAME="${PREFIX}-msa-webapp-${SUFFIX}"
POSTGRES_ADMIN_USER='linkletadmin'
POSTGRES_DB_NAME='clicks'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$CURRENT_DIR/.last_deploy.env"

FAILED=0

# Load the values persisted by deploy.sh (PostgreSQL credentials and endpoint)
if [ -f "$STATE_FILE" ]; then
	source "$STATE_FILE"
else
	echo "State file [$STATE_FILE] not found; run scripts/deploy.sh first. Exiting."
	exit 1
fi

# Retrieve the web app host name
WEB_APP_HOSTNAME=$(az webapp show \
	--name $WEB_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query defaultHostName \
	--output tsv)

if [[ -z "$WEB_APP_HOSTNAME" ]]; then
	echo "Failed to retrieve the host name of the [$WEB_APP_NAME] web app. Exiting."
	exit 1
fi
WEB_APP_URL="http://$WEB_APP_HOSTNAME"

# 1. Wait for the web app health endpoint: it verifies Table Storage, Key Vault and
# PostgreSQL connectivity through the managed identity.
echo "Waiting for the [$WEB_APP_NAME] web app health endpoint..."
HEALTH=""
for i in $(seq 1 60); do
	HEALTH=$(curl -s -m 8 "$WEB_APP_URL/healthz" 2>/dev/null)
	echo "$HEALTH" | grep -q '"status": *"ok"' && break
	sleep 5
done
echo "Health response: $HEALTH"
if echo "$HEALTH" | grep -q '"status": *"ok"'; then
	echo "Health check passed"
else
	echo "Health check failed"
	FAILED=1
fi

# 2. Shorten a benign URL: writes the link to Table Storage, signs it with the Key Vault
# key, sends a Service Bus event and enqueues a QR-render job.
echo "Shortening a benign URL..."
CLEAN_RESPONSE=$(curl -s -X POST "$WEB_APP_URL/shorten" \
	-H "Content-Type: application/json" \
	-d '{"url": "https://github.com/localstack/localstack"}')
echo "$CLEAN_RESPONSE"
CLEAN_CODE=$(echo "$CLEAN_RESPONSE" | jq -r .code)
if [[ -z "$CLEAN_CODE" || "$CLEAN_CODE" == "null" ]]; then
	echo "Failed to shorten the benign URL"
	FAILED=1
fi

# 3. Shorten a suspicious URL: the abuse-scan worker must flag it.
echo "Shortening a suspicious URL..."
FLAGGED_RESPONSE=$(curl -s -X POST "$WEB_APP_URL/shorten" \
	-H "Content-Type: application/json" \
	-d '{"url": "https://bad.example.com/phishing/login"}')
echo "$FLAGGED_RESPONSE"
FLAGGED_CODE=$(echo "$FLAGGED_RESPONSE" | jq -r .code)

# 4. Wait for the workers: AbuseScan consumes the Service Bus event, QrGenerator
# consumes the storage-queue job and renders the QR code into Blob Storage.
echo "Waiting for the AbuseScan and QrGenerator workers..."
SCAN=""
QR=""
for i in $(seq 1 48); do
	LINK_INFO=$(curl -s "$WEB_APP_URL/api/links/$CLEAN_CODE")
	SCAN=$(echo "$LINK_INFO" | jq -r .scan)
	QR=$(echo "$LINK_INFO" | jq -r .qr)
	[[ "$SCAN" == "clean" && "$QR" == "done" ]] && break
	sleep 5
done
echo "Benign link after processing: $LINK_INFO"
if [[ "$SCAN" == "clean" ]]; then
	echo "AbuseScan verdict for the benign link is correct"
else
	echo "AbuseScan did not mark the benign link as clean (scan=$SCAN)"
	FAILED=1
fi
if [[ "$QR" == "done" ]]; then
	echo "QrGenerator rendered the QR code"
else
	echo "QrGenerator did not render the QR code (qr=$QR)"
	FAILED=1
fi

FLAGGED_SCAN=""
for i in $(seq 1 24); do
	FLAGGED_INFO=$(curl -s "$WEB_APP_URL/api/links/$FLAGGED_CODE")
	FLAGGED_SCAN=$(echo "$FLAGGED_INFO" | jq -r .scan)
	[[ "$FLAGGED_SCAN" == "flagged" ]] && break
	sleep 5
done
echo "Suspicious link after processing: $FLAGGED_INFO"
if [[ "$FLAGGED_SCAN" == "flagged" ]]; then
	echo "AbuseScan verdict for the suspicious link is correct"
else
	echo "AbuseScan did not flag the suspicious link (scan=$FLAGGED_SCAN)"
	FAILED=1
fi

# 5. Fetch the rendered QR code from the public blob container.
QR_URL=$(curl -s "$WEB_APP_URL/api/links/$CLEAN_CODE" | jq -r .qr_url)
echo "Fetching the QR code from [$QR_URL]..."
QR_CONTENT_TYPE=$(curl -sk -o /tmp/msa_qr.svg -w "%{content_type}" "$QR_URL")
echo "QR content type: $QR_CONTENT_TYPE"
if grep -q "<svg" /tmp/msa_qr.svg; then
	echo "QR code successfully fetched from Blob Storage"
else
	echo "Failed to fetch the QR code from Blob Storage"
	FAILED=1
fi

# 6. Follow the short link twice: each redirect logs a click row into PostgreSQL.
# The redirect status codes are printed for information only (emulator releases
# without the fix from localstack/localstack-pro#8135 follow the redirect at the
# gateway), so the assertion targets the effect: the click rows in PostgreSQL.
echo "Following the short link twice..."
curl -s -o /dev/null -w "First redirect: %{http_code} -> %{redirect_url}\n" "$WEB_APP_URL/l/$CLEAN_CODE"
curl -s -o /dev/null -w "Second redirect: %{http_code} -> %{redirect_url}\n" "$WEB_APP_URL/l/$CLEAN_CODE"
sleep 3
CLICKS=$(PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" psql \
	--host="$POSTGRES_HOST" \
	--port="$POSTGRES_PORT" \
	--username="$POSTGRES_ADMIN_USER" \
	--dbname="$POSTGRES_DB_NAME" \
	--tuples-only --no-align \
	--command="SELECT count(*) FROM clicks WHERE code='$CLEAN_CODE';" 2>&1)
echo "Clicks logged in PostgreSQL for [$CLEAN_CODE]: $CLICKS"
if [[ "$CLICKS" == "2" ]]; then
	echo "Click logging into PostgreSQL works"
else
	echo "Unexpected click count in PostgreSQL (got: $CLICKS)"
	FAILED=1
fi

# 7. Verify the hit counter in Table Storage through the web app API.
HITS=$(curl -s "$WEB_APP_URL/api/links/$CLEAN_CODE" | jq -r .hits)
echo "Hits recorded in Table Storage for [$CLEAN_CODE]: $HITS"
if [[ "$HITS" == "2" ]]; then
	echo "Hit counting in Table Storage works"
else
	echo "Unexpected hit count in Table Storage (got: $HITS)"
	FAILED=1
fi

# 8. Verify the observability wiring: the Log Analytics workspace exists and the
# storage account has diagnostic settings attached.
echo "Checking the [$LOG_ANALYTICS_NAME] Log Analytics workspace..."
az monitor log-analytics workspace show \
	--workspace-name $LOG_ANALYTICS_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query name \
	--output tsv || FAILED=1
STORAGE_ACCOUNT_ID=$(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)
DIAGNOSTICS=$(az monitor diagnostic-settings list --resource "$STORAGE_ACCOUNT_ID" --query "[].name" --output tsv 2>/dev/null)
echo "Diagnostic settings on the storage account: ${DIAGNOSTICS:-<none>}"
if [[ -z "$DIAGNOSTICS" ]]; then
	echo "No diagnostic settings found on the storage account"
	FAILED=1
fi

if [[ $FAILED == 0 ]]; then
	echo "All validation checks passed"
else
	echo "Some validation checks failed"
fi
exit $FAILED
