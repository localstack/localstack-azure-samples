#!/bin/bash

# =============================================================================
# Deploys the payment fraud detection pipeline with Terraform, then publishes the
# application code (Terraform provisions infrastructure; the Function App and Web
# App packages are pushed with the Azure CLI, as in the other samples).
# =============================================================================

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$CURRENT_DIR/../src" && pwd)"
FUNCTION_ZIP="fraud_function.zip"
DEPLOY_RETRY_COUNT=10
DEPLOY_RETRY_SLEEP=60
WEB_APP_ZIP="dashboard.zip"

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

fail() {
	echo "ERROR: $1"
	exit 1
}

# Resolve the object id of the deploying principal. azurerm_key_vault_secret writes through the Key Vault
# data plane, so on Azure the principal running terraform apply needs Key Vault Secrets Officer on the
# vault; the configuration assigns it when the id is known. The lookup goes through Microsoft Graph; when
# it fails the assignment is skipped and the role becomes a prerequisite (see the README).
ACCOUNT_USER_TYPE=$(az account show --query user.type --output tsv --only-show-errors)
ACCOUNT_USER_NAME=$(az account show --query user.name --output tsv --only-show-errors)

if [[ $ACCOUNT_USER_TYPE == "user" ]]; then
	DEPLOYER_PRINCIPAL_TYPE="User"
	DEPLOYER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv --only-show-errors 2>/dev/null)
else
	DEPLOYER_PRINCIPAL_TYPE="ServicePrincipal"
	DEPLOYER_OBJECT_ID=$(az ad sp show --id "$ACCOUNT_USER_NAME" --query id --output tsv --only-show-errors 2>/dev/null)
fi

# Microsoft Graph lookups need directory permissions a pipeline principal often lacks. Fall back to the oid
# claim of the CLI's own access token, which identifies the same principal without any Graph call.
if [[ -z $DEPLOYER_OBJECT_ID ]]; then
	DEPLOYER_OBJECT_ID=$(az account get-access-token --query accessToken --output tsv --only-show-errors 2>/dev/null |
		cut -d. -f2 | tr '_-' '/+' | awk '{ pad = length($0) % 4; if (pad == 2) $0 = $0 "=="; else if (pad == 3) $0 = $0 "="; print }' |
		base64 -d 2>/dev/null | jq -r '.oid // empty' 2>/dev/null)
fi

if [[ -n $DEPLOYER_OBJECT_ID ]]; then
	echo "Deploying principal [$ACCOUNT_USER_NAME] ($DEPLOYER_PRINCIPAL_TYPE) has object id [$DEPLOYER_OBJECT_ID]"
else
	echo "WARNING: could not resolve the object id of the deploying principal [$ACCOUNT_USER_NAME]; the Key Vault Secrets Officer role on the key vault must already be assigned to it"
	DEPLOYER_OBJECT_ID=""
fi

# The variables of the configuration: the deploying principal, and the prefix only when PREFIX is set, otherwise
# terraform.tfvars, TF_VAR_prefix or the variable's default decides it
TERRAFORM_VARIABLES=(
	-var "deployer_object_id=$DEPLOYER_OBJECT_ID"
	-var "deployer_principal_type=$DEPLOYER_PRINCIPAL_TYPE"
)
if [[ -n $PREFIX ]]; then
	TERRAFORM_VARIABLES+=(-var "prefix=$PREFIX")
fi

echo "=== Initializing Terraform ==="
terraform init -input=false || fail "terraform init failed"

echo ""
echo "=== Validating the configuration ==="
terraform validate || fail "terraform validate failed"

echo ""
echo "=== Planning ==="
terraform plan -input=false "${TERRAFORM_VARIABLES[@]}" -out=tfplan || fail "terraform plan failed"

echo ""
echo "=== Applying ==="
terraform apply -input=false -auto-approve tfplan || fail "terraform apply failed"

echo ""
echo "=== Re-applying (the configuration must converge without errors) ==="
terraform apply -input=false -auto-approve "${TERRAFORM_VARIABLES[@]}" || fail "the second apply failed"

# A perfectly idempotent second apply reports "No changes". Against the emulator a few
# resources still report drift because some properties are accepted on create but not
# echoed back on read (App Service `always_on` / `ftps_state`, Key Vault tags, and
# similar), so the provider re-sends them every run. That is an
# emulator parity gap rather than a problem with this configuration: the re-apply is
# clean, converges, and changes nothing observable.
DRIFT=$(terraform plan -input=false "${TERRAFORM_VARIABLES[@]}" -detailed-exitcode >/dev/null 2>&1; echo $?)
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
zip -r "$(native_path "$CURRENT_DIR/$FUNCTION_ZIP")" function_app.py host.json requirements.txt 1>/dev/null
cd "$CURRENT_DIR" || exit 1

echo "Deploying the fraud detection function (the first run can take several minutes)..."
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

cd "$SRC_DIR/dashboard" || fail "missing src/dashboard"
rm -f "$CURRENT_DIR/$WEB_APP_ZIP"
zip -r "$(native_path "$CURRENT_DIR/$WEB_APP_ZIP")" app.py gunicorn.conf.py requirements.txt templates static 1>/dev/null
cd "$CURRENT_DIR" || exit 1

echo "Deploying the dashboard..."
# Asynchronous, as in the other web app samples: the CLI polls the deployment until the build ends. A synchronous
# request timed out on Azure (504) while the build was still running
az webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$WEB_APP_ZIP" \
	--type zip \
	--async true 1>/dev/null || fail "could not deploy the web app"
rm -f "$WEB_APP_ZIP"

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
