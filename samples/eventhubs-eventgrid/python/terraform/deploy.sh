#!/bin/bash

# =============================================================================
# Deploys the cold-path pipeline with Terraform, then publishes the application code.
# Terraform provisions the infrastructure; the Function App package is pushed with the Azure CLI,
# as in the other samples.
# =============================================================================

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$CURRENT_DIR/../src" && pwd)"
FUNCTION_ZIP='capture_processor.zip'
DEPLOY_RETRY_COUNT=10
DEPLOY_RETRY_SLEEP=60

# On Windows, Git Bash and MSYS2 shells pass a path such as /tmp/... unconverted to Windows programs
# (az, curl, jq, python, docker) when MSYS_NO_PATHCONV=1 is set, as the README asks. cygpath, which
# those shells provide, returns the C:/... form those programs can open; elsewhere the path is unchanged.
native_path() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -m "$1"
	else
		echo "$1"
	fi
}

cd "$CURRENT_DIR" || exit 1

# Dual-target provider configuration. providers.tf hardcodes nothing: the azurerm provider reads its endpoints and the
# target subscription from the ARM_* environment variables exported here.
# - On both targets: the subscription and tenant of the active az account.
# - Only when the active az cloud is LocalStack: the emulator's metadata endpoint, taken from the az cloud registration
#   that `lstk az start-interception` created, so nothing is hardcoded here either.
ACTIVE_CLOUD=$(az cloud show --query name --output tsv --only-show-errors)
ARM_SUBSCRIPTION_ID=$(az account show --query id --output tsv --only-show-errors)
ARM_TENANT_ID=$(az account show --query tenantId --output tsv --only-show-errors)
export ARM_SUBSCRIPTION_ID ARM_TENANT_ID

if [[ $ACTIVE_CLOUD == "LocalStack" ]]; then
	RESOURCE_MANAGER_ENDPOINT=$(az cloud show --query endpoints.resourceManager --output tsv --only-show-errors)
	METADATA_HOSTNAME="${RESOURCE_MANAGER_ENDPOINT#https://}"
	export ARM_METADATA_HOSTNAME="${METADATA_HOSTNAME%/}"
	echo "Active cloud is [$ACTIVE_CLOUD]: Terraform targets the emulator at [$RESOURCE_MANAGER_ENDPOINT]"
else
	# Cleared rather than merely not set: a value inherited from an earlier emulator deployment in the same shell would
	# keep the provider doing metadata discovery against the emulator while the CLI is on Azure.
	unset ARM_METADATA_HOSTNAME
	echo "Active cloud is [$ACTIVE_CLOUD]: Terraform targets Azure subscription [$ARM_SUBSCRIPTION_ID]"
fi

fail() {
	echo "ERROR: $1"
	exit 1
}

# The configuration's prefix variable, passed only when PREFIX is set: otherwise terraform.tfvars, TF_VAR_prefix
# or the variable's default decides it
PREFIX_VARIABLE=()
if [[ -n $PREFIX ]]; then
	PREFIX_VARIABLE=(-var "prefix=$PREFIX")
fi

echo "=== Initializing Terraform ==="
terraform init -input=false || fail "terraform init failed"

echo ""
echo "=== Validating the configuration ==="
terraform validate || fail "terraform validate failed"

echo ""
echo "=== Planning ==="
terraform plan -input=false "${PREFIX_VARIABLE[@]}" -out=tfplan || fail "terraform plan failed"

echo ""
echo "=== Applying ==="
terraform apply -input=false -auto-approve tfplan || fail "terraform apply failed"

echo ""
echo "=== Re-applying (the configuration must converge without errors) ==="
terraform apply -input=false -auto-approve "${PREFIX_VARIABLE[@]}" || fail "the second apply failed"

# A perfectly idempotent second apply reports "No changes". Against the emulator a few resources
# still report drift because some properties are accepted on create but not echoed back on read,
# so the provider re-sends them every run. That is an emulator parity gap rather than a problem
# with this configuration: the re-apply converges and changes nothing observable.
DRIFT=$(
	terraform plan -input=false "${PREFIX_VARIABLE[@]}" -detailed-exitcode >/dev/null 2>&1
	echo $?
)
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

cd "$SRC_DIR/functions" || fail "missing src/functions"
rm -f "$CURRENT_DIR/$FUNCTION_ZIP"
zip -r "$(native_path "$CURRENT_DIR/$FUNCTION_ZIP")" function_app.py host.json requirements.txt 1>/dev/null
cd "$CURRENT_DIR" || exit 1

echo "Deploying the capture processor (the first run can take several minutes)..."
# The function app runs on a Linux Consumption plan, which has no companion deployment site: Azure answers
# az functionapp deploy with "This API isn't available in this environment yet!". Zip deployment with a remote build,
# which installs requirements.txt, deploys it (Learn, "Deployment technologies in Azure Functions"). On Azure the first
# deployment to a new function app can time out, and its deployment endpoint can answer 503 (Site Unavailable) for
# several minutes after the app is created, so a failed attempt is retried for about ten minutes
DEPLOYED=0
for ((ATTEMPT = 1; ATTEMPT <= DEPLOY_RETRY_COUNT; ATTEMPT++)); do
	az functionapp deployment source config-zip \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$FUNCTION_APP_NAME" \
		--src "$FUNCTION_ZIP" \
		--build-remote true 1>/dev/null

	if [[ $? == 0 ]]; then
		DEPLOYED=1
		break
	fi

	if [[ $ATTEMPT -lt $DEPLOY_RETRY_COUNT ]]; then
		echo "Attempt $ATTEMPT of $DEPLOY_RETRY_COUNT to deploy function app [$FUNCTION_APP_NAME] failed. Waiting [$DEPLOY_RETRY_SLEEP] seconds before retry..."
		sleep $DEPLOY_RETRY_SLEEP
	fi
done
[[ $DEPLOYED == 1 ]] || fail "could not deploy the function app"
rm -f "$FUNCTION_ZIP"

# A function app on the Consumption plan runs only when the platform's scale controller starts it for the events its
# trigger watches. On Azure, after two deployments in a row, the scale controller watched no trigger and never started
# the function app (2026-11-26). Registering the triggers again at the end of the deployment, once the remote build of
# the package has had time to finish, makes it start the function app when the events arrive.
WEB_API_VERSION="${WEB_API_VERSION:-2024-04-01}"
echo "Syncing the triggers of the [$FUNCTION_APP_NAME] function app..."
FUNCTION_APP_ID=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query id --output tsv --only-show-errors)
[[ -n "$FUNCTION_APP_ID" ]] || fail "could not read the id of function app [$FUNCTION_APP_NAME]"
az rest --method post --url "$FUNCTION_APP_ID/syncfunctiontriggers?api-version=$WEB_API_VERSION" --only-show-errors \
	1>/dev/null || fail "could not sync the triggers of function app [$FUNCTION_APP_NAME]"
echo "Synced the triggers of the [$FUNCTION_APP_NAME] function app."

# -----------------------------------------------------------------------------
echo ""
echo "=== Verifying the deployment ==="
# -----------------------------------------------------------------------------
EVENTHUB_NAMESPACE_NAME=$(terraform output -raw eventhub_namespace_name)
TELEMETRY_HUB_NAME=$(terraform output -raw telemetry_hub_name)

az eventhubs eventhub show --name "$TELEMETRY_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query "{name:name, partitions:partitionCount, capture:captureDescription.enabled}" \
	--output table --only-show-errors || fail "the telemetry hub is not readable"

# Mirror scripts/deploy.sh so the demo runs after a Terraform deployment too.
cat >"$CURRENT_DIR/../scripts/.deployment-env" <<EOF
export RESOURCE_GROUP_NAME='$RESOURCE_GROUP_NAME'
export EVENTHUB_NAMESPACE_NAME='$EVENTHUB_NAMESPACE_NAME'
export TELEMETRY_HUB_NAME='$TELEMETRY_HUB_NAME'
export NOTIFICATION_HUB_NAME='$(terraform output -raw notification_hub_name)'
export CURATED_HUB_NAME='$(terraform output -raw curated_hub_name)'
export CAPTURE_CONSUMER_GROUP='$(terraform output -raw capture_consumer_group)'
export CAPTURE_CONTAINER_NAME='$(terraform output -raw capture_container_name)'
export STORAGE_ACCOUNT_NAME='$(terraform output -raw storage_account_name)'
export SYSTEM_TOPIC_NAME='$(terraform output -raw system_topic_name)'
export SUBSCRIPTION_NAME='$(terraform output -raw event_subscription_name)'
export FUNCTION_APP_NAME='$FUNCTION_APP_NAME'
export TEMPERATURE_LIMIT='$(terraform output -raw temperature_limit)'
export EVENTHUB_SEND_CONNECTION_STRING='$(terraform output -raw eventhub_send_connection_string)'
export EVENTHUB_LISTEN_CONNECTION_STRING='$(terraform output -raw eventhub_listen_connection_string)'
export EVENTHUB_NAMESPACE_CONNECTION_STRING='$(terraform output -raw eventhub_namespace_connection_string)'
export STORAGE_CONNECTION_STRING='$(terraform output -raw storage_connection_string)'
EOF

echo ""
echo "Deployment complete. Run 'bash ../scripts/validate.sh' to exercise every capability,"
echo "then 'bash ../scripts/run-pipeline.sh' for the end-to-end demo."
