  #!/bin/bash

# =============================================================================
# ACI Vacation Planner - Validation Script
#
# Verifies that all Azure resources were deployed successfully and exercises
# the full ACI lifecycle: create, get, list, logs, exec, stop, start, restart.
# =============================================================================

# Variables (must match deploy.sh)
PREFIX='local'
LOCATION='eastus'
RESOURCE_GROUP_NAME="${PREFIX}-aci-rg"
STORAGE_ACCOUNT_NAME="${PREFIX}acistorage"
KEY_VAULT_NAME="${PREFIX}acikv"
ACR_NAME="${PREFIX}aciacr"
ACI_GROUP_NAME="${PREFIX}-aci-planner"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

PASS_COUNT=0
FAIL_COUNT=0

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	AZ="azlocal"
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
echo "Validating ACI Vacation Planner Deployment"
echo "============================================================"
echo ""

# =============================================================================
# Part 1: Infrastructure Resources
# =============================================================================
echo "--- Part 1: Infrastructure Resources ---"
echo ""

# 1. Resource Group
echo "[1/5] Resource Group"
check "resource group exists" "$AZ group show --name $RESOURCE_GROUP_NAME"
echo ""

# 2. Storage Account
echo "[2/5] Storage Account"
check "storage account exists" "$AZ storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

# 3. Key Vault
echo "[3/5] Key Vault"
check "key vault exists" "$AZ keyvault show --name $KEY_VAULT_NAME --resource-group $RESOURCE_GROUP_NAME"
check "secret exists" "$AZ keyvault secret show --vault-name $KEY_VAULT_NAME --name storage-conn"
echo ""

# 4. Container Registry
echo "[4/5] Container Registry"
check "ACR exists" "$AZ acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

# 5. Container Instance - Get
echo "[5/5] Container Instance"
check "ACI container group exists" "$AZ container show --name $ACI_GROUP_NAME --resource-group $RESOURCE_GROUP_NAME"
echo ""

# Wait for the container group to reach Running state before testing operations
echo -n "  Waiting for container group to be Running... "
for i in $(seq 1 20); do
	STATE=$($AZ container show --name "$ACI_GROUP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query 'instanceView.state' --output tsv 2>/dev/null)
	if [[ "$STATE" == "Running" ]]; then
		break
	fi
	sleep 3
done
if [[ "$STATE" == "Running" ]]; then
	echo "OK"
else
	echo "WARN (state: ${STATE:-unknown}, continuing anyway)"
fi
echo ""

# =============================================================================
# Part 2: ACI Operations
# =============================================================================
echo "--- Part 2: ACI Operations ---"
echo ""

# Check FQDN is set (after wait, so async creation has completed)
check_output "FQDN is set" \
	"$AZ container show --name $ACI_GROUP_NAME --resource-group $RESOURCE_GROUP_NAME --query 'ipAddress.fqdn' --output tsv" \
	"azurecontainer.io"

# 6. List container groups
echo "[6] List Container Groups"
check_output "list returns our group" \
	"$AZ container list --resource-group $RESOURCE_GROUP_NAME --query '[].name' --output tsv" \
	"$ACI_GROUP_NAME"
echo ""

# 7. Container Logs
echo "[7] Container Logs"
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

echo ""

# 8. Container Exec
echo "[8] Container Exec"
echo -n "  Executing command inside container... "
EXEC_OUTPUT=$($AZ container exec \
	--name "$ACI_GROUP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--container-name "$ACI_GROUP_NAME" \
	--exec-command "echo hello-from-exec" 2>/dev/null)

if [ $? -eq 0 ]; then
	echo "OK"
	PASS_COUNT=$((PASS_COUNT + 1))
else
	echo "FAIL"
	FAIL_COUNT=$((FAIL_COUNT + 1))
fi
echo ""

# =============================================================================
# Part 3: ACI Lifecycle (Stop / Start / Restart)
# =============================================================================
echo "--- Part 3: ACI Lifecycle ---"
echo ""

# 9. Stop
echo "[9] Stop Container Group"
echo -n "  Stopping container group... "
$AZ container stop \
	--name "$ACI_GROUP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors 2>/dev/null

if [ $? -eq 0 ]; then
	echo "OK"
	PASS_COUNT=$((PASS_COUNT + 1))
else
	echo "FAIL"
	FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Verify stopped state
check_output "state is Stopped" \
	"$AZ container show --name $ACI_GROUP_NAME --resource-group $RESOURCE_GROUP_NAME --query 'instanceView.state' --output tsv" \
	"Stopped"
echo ""

# 10. Start
echo "[10] Start Container Group"
echo -n "  Starting container group... "
$AZ container start \
	--name "$ACI_GROUP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors 2>/dev/null

if [ $? -eq 0 ]; then
	echo "OK"
	PASS_COUNT=$((PASS_COUNT + 1))
else
	echo "FAIL"
	FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Wait a moment for containers to start
sleep 3

check_output "state is Running" \
	"$AZ container show --name $ACI_GROUP_NAME --resource-group $RESOURCE_GROUP_NAME --query 'instanceView.state' --output tsv" \
	"Running"
echo ""

# 11. Restart
echo "[11] Restart Container Group"
echo -n "  Restarting container group... "
$AZ container restart \
	--name "$ACI_GROUP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors 2>/dev/null

if [ $? -eq 0 ]; then
	echo "OK"
	PASS_COUNT=$((PASS_COUNT + 1))
else
	echo "FAIL"
	FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Wait for restart to complete
sleep 3

check_output "state is Running after restart" \
	"$AZ container show --name $ACI_GROUP_NAME --resource-group $RESOURCE_GROUP_NAME --query 'instanceView.state' --output tsv" \
	"Running"
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "============================================================"
echo "Validation Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "============================================================"

# Show the app URL if a host port is mapped
HOST_PORT=$(docker port "$(docker ps -q --filter "name=ls-aci-${ACI_GROUP_NAME}" | head -1)" 80/tcp 2>/dev/null | head -1 | sed 's/.*://')
FQDN=$($AZ container show --name "$ACI_GROUP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query 'ipAddress.fqdn' --output tsv 2>/dev/null)

if [ -n "$HOST_PORT" ] || [ -n "$FQDN" ]; then
	echo ""
	echo "--- App Access ---"
	if [ -n "$HOST_PORT" ]; then
		echo "Local URL:  http://localhost:$HOST_PORT"
	fi
	if [ -n "$FQDN" ]; then
		echo "FQDN:       http://$FQDN"
	fi
fi
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
	echo "PASS: All checks passed. Vacation Planner is running on ACI."
	exit 0
else
	echo "FAIL: Some checks failed. Review the output above."
	exit 1
fi
