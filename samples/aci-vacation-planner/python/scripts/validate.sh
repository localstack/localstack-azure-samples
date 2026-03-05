#!/bin/bash

# =============================================================================
# ACI Vacation Planner - Validation Script
#
# Verifies that all Azure resources were deployed successfully and the
# container is running with the expected configuration.
# =============================================================================

# Variables (must match deploy.sh)
PREFIX='local'
RESOURCE_GROUP_NAME="${PREFIX}-aci-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}acistorage"
KEY_VAULT_NAME="${PREFIX}acikv"
ACR_NAME="${PREFIX}aciacr"
ACI_GROUP_NAME="${PREFIX}-aci-planner"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

PASS_COUNT=0
FAIL_COUNT=0

# Choose the appropriate CLI based on the environment
# When start_interception is active, 'az' already routes to LocalStack.
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	AZ="az"
else
	AZ="az"
fi

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

echo "============================================================"
echo "Validating ACI Vacation Planner Deployment"
echo "============================================================"
echo ""

# 1. Resource Group
echo "[1/6] Resource Group"
check "resource group exists" "$AZ group show --name $RESOURCE_GROUP_NAME"
echo ""

# 2. Storage Account
echo "[2/6] Storage Account"
check "storage account exists" "$AZ storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

# 3. Key Vault
echo "[3/6] Key Vault"
check "key vault exists" "$AZ keyvault show --name $KEY_VAULT_NAME --resource-group $RESOURCE_GROUP_NAME"
check "secret exists" "$AZ keyvault secret show --vault-name $KEY_VAULT_NAME --name storage-conn"
echo ""

# 4. Container Registry
echo "[4/6] Container Registry"
check "ACR exists" "$AZ acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

# 5. Container Instance
echo "[5/6] Container Instance"
check "ACI container group exists" "$AZ container show --name $ACI_GROUP_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

# 6. Container Logs
echo "[6/6] Container Logs"
echo -n "  Checking container logs for Flask startup... "

# Wait for Flask to start (container may need a few seconds to initialize)
for i in $(seq 1 15); do
	LOGS=$($AZ container logs \
		--name "$ACI_GROUP_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" 2>/dev/null)

	if [ -z "$LOGS" ]; then
		# Fallback: try docker logs directly
		CONTAINER_ID=$(docker ps -q --filter "name=ls-aci-${ACI_GROUP_NAME}" 2>/dev/null | head -1)
		if [ -n "$CONTAINER_ID" ]; then
			LOGS=$(docker logs "$CONTAINER_ID" 2>&1)
		fi
	fi

	if echo "$LOGS" | grep -q "Running on"; then
		break
	elif echo "$LOGS" | grep -q "Serving Flask app"; then
		break
	fi
	sleep 2
done

if echo "$LOGS" | grep -q "Running on"; then
	echo "OK (Flask is running)"
	PASS_COUNT=$((PASS_COUNT + 1))
elif echo "$LOGS" | grep -q "Serving Flask app"; then
	echo "OK (Flask is serving)"
	PASS_COUNT=$((PASS_COUNT + 1))
else
	echo "FAIL (expected Flask startup message not found)"
	FAIL_COUNT=$((FAIL_COUNT + 1))
	if [ -n "$LOGS" ]; then
		echo "  Last few lines of logs:"
		echo "$LOGS" | tail -5 | sed 's/^/    /'
	else
		echo "  No logs available."
	fi
fi

# Summary
echo ""
echo "============================================================"
echo "Validation Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "============================================================"

if [ $FAIL_COUNT -eq 0 ]; then
	echo "PASS: All checks passed. Vacation Planner is running on ACI."
	# Show the app URL if a host port is mapped
	HOST_PORT=$(docker port "$(docker ps -q --filter "name=ls-aci-${ACI_GROUP_NAME}" | head -1)" 80/tcp 2>/dev/null | head -1 | sed 's/.*://')
	if [ -n "$HOST_PORT" ]; then
		echo ""
		echo "App URL: http://localhost:$HOST_PORT"
	fi
	exit 0
else
	echo "FAIL: Some checks failed. Review the output above."
	exit 1
fi
