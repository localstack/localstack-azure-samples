#!/bin/bash

# =============================================================================
# Container Apps Guestbook - Validation Script
#
# Verifies that all Azure resources were deployed successfully and exercises
# the Container Apps surface: environment, app properties, secrets, revisions,
# replicas, the live HTTP ingress, and a revision update.
# =============================================================================

# Variables (must match deploy.sh)
PREFIX='local'
LOCATION='eastus'
RESOURCE_GROUP_NAME="${PREFIX}-aca-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}acastorage"
BLOB_CONTAINER_NAME="guestbook"
ACR_NAME="${PREFIX}acaacr"
ACA_ENV_NAME="${PREFIX}-aca-env"
ACA_APP_NAME="${PREFIX}-aca-guestbook"

PASS_COUNT=0
FAIL_COUNT=0

check() {
	local description="$1"
	local command="$2"

	echo -n "  Checking $description... "
	eval "$command" &>/dev/null
	if [ $? -eq 0 ]; then
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
	OUTPUT=$(eval "$command" 2>/dev/null)
	if echo "$OUTPUT" | grep -q "$expected"; then
		echo "OK"
		PASS_COUNT=$((PASS_COUNT + 1))
	else
		echo "FAIL (expected '$expected')"
		FAIL_COUNT=$((FAIL_COUNT + 1))
	fi
}

echo "============================================================"
echo "Validating Container Apps Guestbook Deployment"
echo "============================================================"
echo ""

# =============================================================================
# Part 1: Infrastructure Resources
# =============================================================================
echo "--- Part 1: Infrastructure Resources ---"
echo ""

# 1. Resource Group
echo "[1/5] Resource Group"
check "resource group exists" "az group show --name $RESOURCE_GROUP_NAME"
echo ""

# 2. Storage Account
echo "[2/5] Storage Account"
check "storage account exists" "az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

# 3. Container Registry
echo "[3/5] Container Registry"
check "ACR exists" "az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

# 4. Container Apps Environment
echo "[4/5] Container Apps Environment"
check "environment exists" "az containerapp env show --name $ACA_ENV_NAME --resource-group $RESOURCE_GROUP_NAME"
check_output "environment is provisioned" \
	"az containerapp env show --name $ACA_ENV_NAME --resource-group $RESOURCE_GROUP_NAME --query 'properties.provisioningState' --output tsv" \
	"Succeeded"
echo ""

# 5. Container App
echo "[5/5] Container App"
check "container app exists" "az containerapp show --name $ACA_APP_NAME --resource-group $RESOURCE_GROUP_NAME"
check_output "app is provisioned" \
	"az containerapp show --name $ACA_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query 'properties.provisioningState' --output tsv" \
	"Succeeded"
check_output "app is running" \
	"az containerapp show --name $ACA_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query 'properties.runningStatus' --output tsv" \
	"Running"
echo ""

# =============================================================================
# Part 2: Container App Configuration
# =============================================================================
echo "--- Part 2: Container App Configuration ---"
echo ""

APP_SHOW="az containerapp show --name $ACA_APP_NAME --resource-group $RESOURCE_GROUP_NAME"

# 6. Ingress
echo "[6] Ingress"
FQDN=$(eval "$APP_SHOW --query 'properties.configuration.ingress.fqdn' --output tsv" 2>/dev/null)
echo -n "  Checking ingress FQDN is set... "
if [ -n "$FQDN" ]; then
	echo "OK ($FQDN)"
	PASS_COUNT=$((PASS_COUNT + 1))
else
	echo "FAIL"
	FAIL_COUNT=$((FAIL_COUNT + 1))
fi
check_output "ingress is external" \
	"$APP_SHOW --query 'properties.configuration.ingress.external' --output tsv" \
	"true"
check_output "target port is 8080" \
	"$APP_SHOW --query 'properties.configuration.ingress.targetPort' --output tsv" \
	"8080"
echo ""

# 7. Secrets
echo "[7] Secrets"
check_output "secret [storage-conn] exists" \
	"az containerapp secret list --name $ACA_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query '[].name' --output tsv" \
	"storage-conn"
check_output "secret value is readable" \
	"az containerapp secret show --name $ACA_APP_NAME --resource-group $RESOURCE_GROUP_NAME --secret-name storage-conn --query 'value' --output tsv" \
	"AccountName=${STORAGE_ACCOUNT_NAME}"
check_output "env var is wired to the secret" \
	"$APP_SHOW --query \"properties.template.containers[0].env[?name=='AZURE_STORAGE_CONNECTION_STRING'].secretRef | [0]\" --output tsv" \
	"storage-conn"
echo ""

# 8. Scale
echo "[8] Scale"
check_output "min replicas is 1" \
	"$APP_SHOW --query 'properties.template.scale.minReplicas' --output tsv" \
	"1"
check_output "max replicas is 3" \
	"$APP_SHOW --query 'properties.template.scale.maxReplicas' --output tsv" \
	"3"
check_output "http scale rule is set" \
	"$APP_SHOW --query 'properties.template.scale.rules[0].name' --output tsv" \
	"http-scale"
echo ""

# =============================================================================
# Part 3: Revisions and Replicas
# =============================================================================
echo "--- Part 3: Revisions and Replicas ---"
echo ""

# 9. Revisions
echo "[9] Revisions"
check_output "revision v1 exists" \
	"az containerapp revision list --name $ACA_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query '[].name' --output tsv" \
	"${ACA_APP_NAME}--v1"
LATEST_REVISION=$(eval "$APP_SHOW --query 'properties.latestRevisionName' --output tsv" 2>/dev/null)
echo "  Latest revision: $LATEST_REVISION"
echo ""

# 10. Replicas
echo "[10] Replicas"
echo -n "  Checking a replica is running... "
REPLICA_NAME=""
for i in $(seq 1 20); do
	REPLICA_NAME=$(az containerapp replica list \
		--name "$ACA_APP_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--revision "$LATEST_REVISION" \
		--query "[0].name" --output tsv 2>/dev/null)
	if [ -n "$REPLICA_NAME" ]; then
		break
	fi
	sleep 3
done
if [ -n "$REPLICA_NAME" ]; then
	echo "OK ($REPLICA_NAME)"
	PASS_COUNT=$((PASS_COUNT + 1))
else
	echo "FAIL"
	FAIL_COUNT=$((FAIL_COUNT + 1))
fi
echo ""

# =============================================================================
# Part 4: HTTP Ingress (live app)
# =============================================================================
echo "--- Part 4: HTTP Ingress ---"
echo ""

# On LocalStack the FQDN resolves to 127.0.0.1 and the ingress listens on the
# gateway port; on real Azure the app is served on 443.
if [[ "$FQDN" == *"localhost.localstack.cloud" ]]; then
	APP_URL="http://${FQDN}:4566"
else
	APP_URL="https://${FQDN}"
fi
echo "App URL: $APP_URL"

# 11. Health endpoint (wait for the app to come up; the image may still be pulling)
echo "[11] Health Endpoint"
echo -n "  Waiting for /health to answer... "
HEALTH=""
for i in $(seq 1 30); do
	HEALTH=$(curl -s --max-time 5 "$APP_URL/health" 2>/dev/null)
	if echo "$HEALTH" | grep -q "healthy"; then
		break
	fi
	sleep 3
done
if echo "$HEALTH" | grep -q "healthy"; then
	echo "OK"
	PASS_COUNT=$((PASS_COUNT + 1))
else
	echo "FAIL (no healthy response from $APP_URL/health)"
	FAIL_COUNT=$((FAIL_COUNT + 1))
fi
check_output "storage is configured in the app" \
	"curl -s --max-time 5 $APP_URL/health" \
	'"storage_configured": *true'
echo ""

# 12. Guestbook round trip (POST an entry, read it back)
echo "[12] Guestbook Round Trip"
ENTRY_AUTHOR="validate-sh"
ENTRY_MESSAGE="Hello from validate.sh at $(date +%s)"
echo -n "  Posting a guestbook entry... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
	-X POST "$APP_URL/" \
	--data-urlencode "author=$ENTRY_AUTHOR" \
	--data-urlencode "message=$ENTRY_MESSAGE" 2>/dev/null)
if [[ "$HTTP_CODE" == "302" || "$HTTP_CODE" == "200" ]]; then
	echo "OK (HTTP $HTTP_CODE)"
	PASS_COUNT=$((PASS_COUNT + 1))
else
	echo "FAIL (HTTP $HTTP_CODE)"
	FAIL_COUNT=$((FAIL_COUNT + 1))
fi
check_output "entry is served back from Blob Storage" \
	"curl -s --max-time 10 $APP_URL/" \
	"$ENTRY_MESSAGE"
echo ""

# =============================================================================
# Part 5: Revision Update
# =============================================================================
echo "--- Part 5: Revision Update ---"
echo ""

# 13. Roll out a new revision (v2) with an updated APP_REVISION env var.
# The secretref is re-stated alongside the changed var so the update payload
# carries the secret wiring explicitly rather than relying on the CLI's
# read-modify-write merge of the env list.
echo "[13] Revision Update"
echo -n "  Rolling out revision v2... "
az containerapp update \
	--name "$ACA_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--revision-suffix v2 \
	--set-env-vars \
		APP_REVISION=v2 \
		AZURE_STORAGE_CONNECTION_STRING=secretref:storage-conn \
	--only-show-errors 1>/dev/null 2>&1

if [ $? -eq 0 ]; then
	echo "OK"
	PASS_COUNT=$((PASS_COUNT + 1))
else
	echo "FAIL"
	FAIL_COUNT=$((FAIL_COUNT + 1))
fi

check_output "revision v2 exists" \
	"az containerapp revision list --name $ACA_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query '[].name' --output tsv" \
	"${ACA_APP_NAME}--v2"
check_output "latest revision is v2" \
	"$APP_SHOW --query 'properties.latestRevisionName' --output tsv" \
	"${ACA_APP_NAME}--v2"

# The ingress routes to the latest revision; wait for v2 replicas to serve.
echo -n "  Waiting for revision v2 to serve traffic... "
SERVED_REVISION=""
for i in $(seq 1 30); do
	SERVED_REVISION=$(curl -s --max-time 5 "$APP_URL/health" 2>/dev/null | grep -o '"revision": *"[^"]*"')
	if echo "$SERVED_REVISION" | grep -q "v2"; then
		break
	fi
	sleep 3
done
if echo "$SERVED_REVISION" | grep -q "v2"; then
	echo "OK"
	PASS_COUNT=$((PASS_COUNT + 1))
else
	echo "FAIL (still serving: ${SERVED_REVISION:-no response})"
	FAIL_COUNT=$((FAIL_COUNT + 1))
fi

check_output "entries survive the revision switch" \
	"curl -s --max-time 10 $APP_URL/" \
	"$ENTRY_MESSAGE"
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "============================================================"
echo "Validation Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "============================================================"
echo ""
echo "--- App Access ---"
echo "App URL:  $APP_URL"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
	echo "PASS: All checks passed. Guestbook is running on Azure Container Apps."
	exit 0
else
	echo "FAIL: Some checks failed. Review the output above."
	exit 1
fi
