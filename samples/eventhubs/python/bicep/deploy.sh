#!/bin/bash

# =============================================================================
# Deploys the payment fraud detection pipeline with Bicep, then publishes the
# application code (Bicep provisions infrastructure; the Function App and Web App
# packages are pushed with the Azure CLI, as in the other samples).
# =============================================================================

PREFIX='local'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-eventhubs-rg"
DEPLOYMENT_NAME="eventhubs-fraud-detection"
FUNCTION_ZIP="fraud_function.zip"
WEB_APP_ZIP="dashboard.zip"

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$CURRENT_DIR/../src" && pwd)"

cd "$CURRENT_DIR" || exit 1

fail() {
	echo "ERROR: $1"
	exit 1
}

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
	--only-show-errors 1>/dev/null || fail "the Bicep template did not pass validation"

echo ""
echo "=== Deploying the template ==="
az deployment group create \
	--name "$DEPLOYMENT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--template-file main.bicep \
	--parameters main.bicepparam \
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
NAMESPACE_CONNECTION=$(az eventhubs namespace authorization-rule keys list \
	--name RootManageSharedAccessKey --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query primaryConnectionString -o tsv --only-show-errors)

az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name eventhub-send-connection \
	--value "$SEND_CONNECTION" --only-show-errors 1>/dev/null || fail "could not store the send secret"
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name eventhub-listen-connection \
	--value "$LISTEN_CONNECTION" --only-show-errors 1>/dev/null || fail "could not store the listen secret"
az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name storage-connection \
	--value "$STORAGE_CONNECTION_STRING" --only-show-errors 1>/dev/null || fail "could not store the storage secret"
echo "Stored the connection strings as Key Vault secrets."

az functionapp config appsettings set --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--settings "AzureWebJobsStorage=$STORAGE_CONNECTION_STRING" \
	"WEBSITE_CONTENTAZUREFILECONNECTIONSTRING=$STORAGE_CONNECTION_STRING" \
	"EVENTHUB_LISTEN_CONNECTION=$LISTEN_CONNECTION" \
	"EVENTHUB_SEND_CONNECTION=$ALERT_SEND_CONNECTION" \
	--only-show-errors 1>/dev/null || fail "could not set the function app settings"

az webapp config appsettings set --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--settings "EVENTHUB_LISTEN_CONNECTION_STRING=$NAMESPACE_CONNECTION" \
	"STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING" \
	--only-show-errors 1>/dev/null || fail "could not set the web app settings"
echo "Configured both workloads."

# -----------------------------------------------------------------------------
echo ""
echo "=== Publishing the application code ==="
# -----------------------------------------------------------------------------
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
az eventhubs eventhub show \
	--name "$EVENT_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "{name:name, partitions:partitionCount, capture:captureDescription.enabled}" \
	--output table --only-show-errors || fail "the payments hub is not readable"

echo ""
echo "Dashboard: $DASHBOARD_URL"
echo ""
echo "Deployment complete. Run 'bash ../scripts/validate.sh' to exercise every capability."
