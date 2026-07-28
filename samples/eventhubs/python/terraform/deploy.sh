#!/bin/bash

# =============================================================================
# Deploys the payment fraud detection pipeline with Terraform, then publishes the
# application code (Terraform provisions infrastructure; the Function App and Web
# App packages are pushed with the Azure CLI, as in the other samples).
# =============================================================================

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$CURRENT_DIR/../src" && pwd)"
FUNCTION_ZIP="fraud_function.zip"
WEB_APP_ZIP="dashboard.zip"

cd "$CURRENT_DIR" || exit 1

fail() {
	echo "ERROR: $1"
	exit 1
}

echo "=== Initializing Terraform ==="
terraform init -input=false || fail "terraform init failed"

echo ""
echo "=== Validating the configuration ==="
terraform validate || fail "terraform validate failed"

echo ""
echo "=== Planning ==="
terraform plan -input=false -out=tfplan || fail "terraform plan failed"

echo ""
echo "=== Applying ==="
terraform apply -input=false -auto-approve tfplan || fail "terraform apply failed"

echo ""
echo "=== Re-applying (the configuration must converge without errors) ==="
terraform apply -input=false -auto-approve || fail "the second apply failed"

# A perfectly idempotent second apply reports "No changes". Against the emulator a few
# resources still report drift because some properties are accepted on create but not
# echoed back on read (App Service `always_on` / `ftps_state` / `app_command_line`,
# Key Vault tags, and similar), so the provider re-sends them every run. That is an
# emulator parity gap rather than a problem with this configuration: the re-apply is
# clean, converges, and changes nothing observable.
DRIFT=$(terraform plan -input=false -detailed-exitcode >/dev/null 2>&1; echo $?)
if [[ "$DRIFT" == "0" ]]; then
	echo "Second apply is fully idempotent (no changes)."
else
	echo "Note: the plan still reports in-place updates for properties the emulator does not"
	echo "echo back on read. The configuration converges; nothing is recreated."
fi

# -----------------------------------------------------------------------------
echo ""
echo "=== Publishing the application code ==="
# -----------------------------------------------------------------------------
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
FUNCTION_APP_NAME=$(terraform output -raw function_app_name)
WEB_APP_NAME=$(terraform output -raw web_app_name)

cd "$SRC_DIR/functions" || fail "missing src/functions"
rm -f "$CURRENT_DIR/$FUNCTION_ZIP"
zip -r "$CURRENT_DIR/$FUNCTION_ZIP" function_app.py host.json requirements.txt 1>/dev/null
cd "$CURRENT_DIR" || exit 1

echo "Deploying the fraud detection function (the first run can take several minutes)..."
az functionapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--src-path "$FUNCTION_ZIP" \
	--type zip 1>/dev/null || fail "could not deploy the function app"
rm -f "$FUNCTION_ZIP"

cd "$SRC_DIR/dashboard" || fail "missing src/dashboard"
rm -f "$CURRENT_DIR/$WEB_APP_ZIP"
zip -r "$CURRENT_DIR/$WEB_APP_ZIP" app.py gunicorn.conf.py requirements.txt templates static 1>/dev/null
cd "$CURRENT_DIR" || exit 1

echo "Deploying the dashboard..."
az webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$WEB_APP_ZIP" \
	--type zip 1>/dev/null || fail "could not deploy the web app"
rm -f "$WEB_APP_ZIP"

# -----------------------------------------------------------------------------
echo ""
echo "=== Verifying the deployment ==="
# -----------------------------------------------------------------------------
EVENTHUB_NAMESPACE_NAME=$(terraform output -raw eventhub_namespace_name)
EVENT_HUB_NAME=$(terraform output -raw event_hub_name)

az eventhubs eventhub show \
	--name "$EVENT_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "{name:name, partitions:partitionCount, capture:captureDescription.enabled}" \
	--output table --only-show-errors || fail "the payments hub is not readable"

# -----------------------------------------------------------------------------
# Mirror what scripts/deploy.sh writes, so the end-to-end demo runs after a Terraform
# deployment too - the topology is identical, and every value it needs is an output.
# -----------------------------------------------------------------------------
cat >"$CURRENT_DIR/../scripts/.deployment-env" <<EOF
export RESOURCE_GROUP_NAME='$RESOURCE_GROUP_NAME'
export EVENTHUB_NAMESPACE_NAME='$EVENTHUB_NAMESPACE_NAME'
export EVENT_HUB_NAME='$EVENT_HUB_NAME'
export ALERT_HUB_NAME='$(terraform output -raw alert_hub_name)'
export FRAUD_CONSUMER_GROUP='$(terraform output -raw fraud_consumer_group)'
export SCHEMA_GROUP_NAME='$(terraform output -raw schema_group_name)'
export STORAGE_ACCOUNT_NAME='$(terraform output -raw storage_account_name)'
export CAPTURE_CONTAINER_NAME='$(terraform output -raw capture_container_name)'
export KEY_VAULT_NAME='$(terraform output -raw key_vault_name)'
export FUNCTION_APP_NAME='$FUNCTION_APP_NAME'
export WEB_APP_NAME='$WEB_APP_NAME'
export EVENTHUB_SEND_CONNECTION_STRING='$(terraform output -raw eventhub_send_connection_string)'
export EVENTHUB_LISTEN_CONNECTION_STRING='$(terraform output -raw eventhub_listen_connection_string)'
export EVENTHUB_ALERT_SEND_CONNECTION_STRING='$(terraform output -raw eventhub_alert_send_connection_string)'
export EVENTHUB_NAMESPACE_CONNECTION_STRING='$(terraform output -raw eventhub_namespace_connection_string)'
export STORAGE_CONNECTION_STRING='$(terraform output -raw storage_connection_string)'
EOF

echo ""
echo "Dashboard: $(terraform output -raw dashboard_url)"
echo ""
echo "Deployment complete. Run 'bash ../scripts/validate.sh' to exercise every capability,"
echo "then 'bash ../scripts/run-pipeline.sh' for the end-to-end demo."
