#!/bin/bash

# =============================================================================
# Deploys the payment fraud detection pipeline with Bicep, then publishes the
# application code (Bicep provisions infrastructure; the Function App and Web App
# packages are pushed with the Azure CLI, as in the other samples).
# =============================================================================

PREFIX="${PREFIX:-local}"
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-eventhubs-rg"
DEPLOYMENT_NAME="eventhubs-fraud-detection"
FUNCTION_ZIP="fraud_function.zip"
DEPLOY_RETRY_COUNT=3
DEPLOY_RETRY_SLEEP=30
WEB_APP_ZIP="dashboard.zip"
KEY_VAULT_SECRETS_OFFICER_ROLE='Key Vault Secrets Officer'
ROLE_ASSIGNMENT_RETRY_COUNT=3
ROLE_ASSIGNMENT_RETRY_SLEEP=5
SECRET_RETRY_COUNT=20
SECRET_RETRY_SLEEP=15

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$CURRENT_DIR/../src" && pwd)"

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

# Store a secret in the key vault. The deploying principal can write through the Key Vault data plane only once its
# Key Vault Secrets Officer assignment has propagated, which takes a few minutes on Azure, so the write is retried. The
# value is never printed.
# $1: the secret name
# $2: the secret value
set_secret() {
	local secret_name=$1
	local secret_value=$2
	local attempt error

	for attempt in $(seq 1 "$SECRET_RETRY_COUNT"); do
		if error=$(az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "$secret_name" \
			--value "$secret_value" --only-show-errors 2>&1 1>/dev/null); then
			return 0
		fi
		if [ "$attempt" -lt "$SECRET_RETRY_COUNT" ]; then
			echo "Attempt $attempt of $SECRET_RETRY_COUNT: the [$secret_name] secret could not be stored yet. Waiting [$SECRET_RETRY_SLEEP] seconds before retry..."
			sleep "$SECRET_RETRY_SLEEP"
		fi
	done
	echo "$error"
	fail "could not store the [$secret_name] secret"
}

# Resolve the object id of the deploying principal, a user or a service principal. The vault uses the RBAC permission
# model, so writing the secrets needs the Key Vault Secrets Officer role on the vault. The lookup goes through Microsoft
# Graph, with the oid claim of the CLI's own access token as the fallback for a principal that lacks directory
# permissions; when both fail the role must already be assigned.
ACCOUNT_USER_TYPE=$(az account show --query user.type --output tsv --only-show-errors)
ACCOUNT_USER_NAME=$(az account show --query user.name --output tsv --only-show-errors)

if [[ $ACCOUNT_USER_TYPE == "user" ]]; then
	DEPLOYER_PRINCIPAL_TYPE="User"
	DEPLOYER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv --only-show-errors 2>/dev/null)
else
	DEPLOYER_PRINCIPAL_TYPE="ServicePrincipal"
	DEPLOYER_OBJECT_ID=$(az ad sp show --id "$ACCOUNT_USER_NAME" --query id --output tsv --only-show-errors 2>/dev/null)
fi

if [[ -z $DEPLOYER_OBJECT_ID ]]; then
	DEPLOYER_OBJECT_ID=$(az account get-access-token --query accessToken --output tsv --only-show-errors 2>/dev/null |
		cut -d. -f2 | tr '_-' '/+' | awk '{ pad = length($0) % 4; if (pad == 2) $0 = $0 "=="; else if (pad == 3) $0 = $0 "="; print }' |
		base64 -d 2>/dev/null | jq -r '.oid // empty' 2>/dev/null)
fi

if [[ -n $DEPLOYER_OBJECT_ID ]]; then
	echo "Deploying principal [$ACCOUNT_USER_NAME] ($DEPLOYER_PRINCIPAL_TYPE) has object id [$DEPLOYER_OBJECT_ID]."
else
	echo "WARNING: could not resolve the object id of the deploying principal [$ACCOUNT_USER_NAME]; the [$KEY_VAULT_SECRETS_OFFICER_ROLE] role on the key vault must already be assigned to it."
fi

echo "=== Creating the resource group ==="
az group create \
	--name "$RESOURCE_GROUP_NAME" \
	--location "$LOCATION" \
	--only-show-errors 1>/dev/null || fail "could not create the resource group"
echo "Resource group [$RESOURCE_GROUP_NAME] ready."

echo ""
echo "=== Validating the Bicep template ==="
az deployment group validate \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--template-file main.bicep \
	--parameters main.bicepparam \
	--parameters prefix="$PREFIX" \
	--parameters deployerPrincipalId="$DEPLOYER_OBJECT_ID" deployerPrincipalType="$DEPLOYER_PRINCIPAL_TYPE" \
	--only-show-errors 1>/dev/null || fail "the Bicep template did not pass validation"

echo ""
echo "=== Deploying the template ==="
az deployment group create \
	--name "$DEPLOYMENT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--template-file main.bicep \
	--parameters main.bicepparam \
	--parameters prefix="$PREFIX" \
	--parameters deployerPrincipalId="$DEPLOYER_OBJECT_ID" deployerPrincipalType="$DEPLOYER_PRINCIPAL_TYPE" \
	--only-show-errors 1>/dev/null || fail "the Bicep deployment failed"
echo "Template deployed."

# -----------------------------------------------------------------------------
echo ""
echo "=== Reading the deployment outputs ==="
# -----------------------------------------------------------------------------
outputs=$(az deployment group show \
	--name "$DEPLOYMENT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query properties.outputs \
	--output json --only-show-errors)

FUNCTION_APP_NAME=$(echo "$outputs" | jq -r '.functionAppName.value')
WEB_APP_NAME=$(echo "$outputs" | jq -r '.webAppName.value')
EVENTHUB_NAMESPACE_NAME=$(echo "$outputs" | jq -r '.eventHubNamespaceName.value')
EVENT_HUB_NAME=$(echo "$outputs" | jq -r '.eventHubName.value')
DASHBOARD_URL=$(echo "$outputs" | jq -r '.dashboardUrl.value')

[[ -n "$FUNCTION_APP_NAME" && "$FUNCTION_APP_NAME" != "null" ]] || fail "could not read the deployment outputs"
echo "Function App: $FUNCTION_APP_NAME"
echo "Web App:      $WEB_APP_NAME"

# -----------------------------------------------------------------------------
echo ""
echo "=== Wiring the connection strings ==="
# -----------------------------------------------------------------------------
# Deliberately done here rather than in the template: connection strings are built from keys
# that only exist once the resources do, and anything a template emits as an output is kept
# in the deployment history. Reading them with the CLI keeps the secrets out of both.
STORAGE_ACCOUNT_NAME=$(echo "$outputs" | jq -r '.storageAccountName.value')
KEY_VAULT_NAME=$(echo "$outputs" | jq -r '.keyVaultName.value')
CAPTURE_CONTAINER_NAME=$(echo "$outputs" | jq -r '.captureContainerName.value')
SCHEMA_GROUP_NAME=$(echo "$outputs" | jq -r '.schemaGroupName.value')
ALERT_HUB_NAME=$(echo "$outputs" | jq -r '.alertHubName.value')
FRAUD_CONSUMER_GROUP='fraud-detector'

STORAGE_KEY=$(az storage account keys list --account-name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query "[0].value" -o tsv --only-show-errors)
STORAGE_BLOB=$(az storage account show -n "$STORAGE_ACCOUNT_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query primaryEndpoints.blob -o tsv --only-show-errors)
STORAGE_QUEUE=$(az storage account show -n "$STORAGE_ACCOUNT_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query primaryEndpoints.queue -o tsv --only-show-errors)
STORAGE_TABLE=$(az storage account show -n "$STORAGE_ACCOUNT_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query primaryEndpoints.table -o tsv --only-show-errors)
# Explicit endpoints, not EndpointSuffix: the Functions host cannot parse a suffix carrying a port.
STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_KEY};BlobEndpoint=${STORAGE_BLOB};QueueEndpoint=${STORAGE_QUEUE};TableEndpoint=${STORAGE_TABLE}"

SEND_CONNECTION=$(az eventhubs eventhub authorization-rule keys list --name payments-send \
	--eventhub-name "$EVENT_HUB_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query primaryConnectionString -o tsv --only-show-errors)
LISTEN_CONNECTION=$(az eventhubs eventhub authorization-rule keys list --name payments-listen \
	--eventhub-name "$EVENT_HUB_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query primaryConnectionString -o tsv --only-show-errors)
# Scoped to the alerts hub: an entity-level rule carries EntityPath, so the payments rule
# would pin the output binding to the wrong hub.
ALERT_SEND_CONNECTION=$(az eventhubs eventhub authorization-rule keys list --name alerts-send \
	--eventhub-name "$ALERT_HUB_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query primaryConnectionString -o tsv --only-show-errors)
# The dashboard is a pure reader, so it gets the namespace-wide Listen rule rather than
# RootManageSharedAccessKey.
DASHBOARD_LISTEN_CONNECTION=$(az eventhubs namespace authorization-rule keys list \
	--name dashboard-listen --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query primaryConnectionString -o tsv --only-show-errors)
# Not given to any workload - the demo scripts need it to publish over Kafka and to read
# both hubs, and it is written to scripts/.deployment-env below.
NAMESPACE_CONNECTION=$(az eventhubs namespace authorization-rule keys list \
	--name RootManageSharedAccessKey --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query primaryConnectionString -o tsv --only-show-errors)

# The template gave the deploying principal Key Vault Secrets Officer on the vault; set_secret waits for it to propagate
set_secret eventhub-send-connection "$SEND_CONNECTION"
set_secret eventhub-listen-connection "$LISTEN_CONNECTION"
set_secret storage-connection "$STORAGE_CONNECTION_STRING"
echo "Stored the connection strings as Key Vault secrets."

az functionapp config appsettings set --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--settings "AzureWebJobsStorage=$STORAGE_CONNECTION_STRING" \
	"WEBSITE_CONTENTAZUREFILECONNECTIONSTRING=$STORAGE_CONNECTION_STRING" \
	"EVENTHUB_LISTEN_CONNECTION=$LISTEN_CONNECTION" \
	"EVENTHUB_SEND_CONNECTION=$ALERT_SEND_CONNECTION" \
	--only-show-errors 1>/dev/null || fail "could not set the function app settings"

az webapp config appsettings set --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--settings "EVENTHUB_LISTEN_CONNECTION_STRING=$DASHBOARD_LISTEN_CONNECTION" \
	"STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING" \
	--only-show-errors 1>/dev/null || fail "could not set the web app settings"
echo "Configured both workloads."

# -----------------------------------------------------------------------------
echo ""
echo "=== Publishing the application code ==="
# -----------------------------------------------------------------------------
cd "$SRC_DIR/functions" || fail "missing src/functions"
rm -f "$CURRENT_DIR/$FUNCTION_ZIP"
zip -r "$(native_path "$CURRENT_DIR/$FUNCTION_ZIP")" function_app.py host.json requirements.txt 1>/dev/null
cd "$CURRENT_DIR" || exit 1

echo "Deploying the fraud detection function (the first run can take several minutes)..."
# On Azure the first deployment to a new function app can time out (504) while its deployment site starts, so a failed
# attempt is retried
DEPLOYED=0
for ((ATTEMPT = 1; ATTEMPT <= DEPLOY_RETRY_COUNT; ATTEMPT++)); do
	az functionapp deploy \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$FUNCTION_APP_NAME" \
		--src-path "$FUNCTION_ZIP" \
		--type zip 1>/dev/null

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
az eventhubs eventhub show \
	--name "$EVENT_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "{name:name, partitions:partitionCount, capture:captureDescription.enabled}" \
	--output table --only-show-errors || fail "the payments hub is not readable"

# -----------------------------------------------------------------------------
# Mirror what scripts/deploy.sh writes, so the end-to-end demo runs after a Bicep
# deployment too - the topology is identical, and every value it needs is already here.
# -----------------------------------------------------------------------------
cat >"$CURRENT_DIR/../scripts/.deployment-env" <<EOF
export RESOURCE_GROUP_NAME='$RESOURCE_GROUP_NAME'
export EVENTHUB_NAMESPACE_NAME='$EVENTHUB_NAMESPACE_NAME'
export EVENT_HUB_NAME='$EVENT_HUB_NAME'
export ALERT_HUB_NAME='$ALERT_HUB_NAME'
export FRAUD_CONSUMER_GROUP='$FRAUD_CONSUMER_GROUP'
export SCHEMA_GROUP_NAME='$SCHEMA_GROUP_NAME'
export STORAGE_ACCOUNT_NAME='$STORAGE_ACCOUNT_NAME'
export CAPTURE_CONTAINER_NAME='$CAPTURE_CONTAINER_NAME'
export KEY_VAULT_NAME='$KEY_VAULT_NAME'
export FUNCTION_APP_NAME='$FUNCTION_APP_NAME'
export WEB_APP_NAME='$WEB_APP_NAME'
export EVENTHUB_SEND_CONNECTION_STRING='$SEND_CONNECTION'
export EVENTHUB_LISTEN_CONNECTION_STRING='$LISTEN_CONNECTION'
export EVENTHUB_ALERT_SEND_CONNECTION_STRING='$ALERT_SEND_CONNECTION'
export EVENTHUB_NAMESPACE_CONNECTION_STRING='$NAMESPACE_CONNECTION'
export STORAGE_CONNECTION_STRING='$STORAGE_CONNECTION_STRING'
EOF

echo ""
echo "Dashboard: $DASHBOARD_URL"
echo ""
echo "Deployment complete. Run 'bash ../scripts/validate.sh' to exercise every capability,"
echo "then 'bash ../scripts/run-pipeline.sh' for the end-to-end demo."
