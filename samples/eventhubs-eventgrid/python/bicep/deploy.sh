#!/bin/bash

# =============================================================================
# Deploys the cold-path pipeline with Bicep, then publishes the application code.
# Bicep provisions the infrastructure; the Function App package is pushed with the Azure CLI, as
# in the other samples.
# =============================================================================

PREFIX='local'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-ehgrid-rg"
DEPLOYMENT_NAME='eventhubs-eventgrid-coldpath'
FUNCTION_ZIP='capture_processor.zip'

CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(cd "$CURRENT_DIR/../src" && pwd)"
cd "$CURRENT_DIR" || exit 1

fail() {
	echo "ERROR: $1"
	exit 1
}

echo "=== Creating the resource group ==="
az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" \
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

echo ""
echo "=== Reading the deployment outputs ==="
outputs=$(az deployment group show --name "$DEPLOYMENT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query properties.outputs \
	--output json --only-show-errors)

EVENTHUB_NAMESPACE_NAME=$(echo "$outputs" | jq -r '.eventHubNamespaceName.value')
TELEMETRY_HUB_NAME=$(echo "$outputs" | jq -r '.telemetryHubName.value')
NOTIFICATION_HUB_NAME=$(echo "$outputs" | jq -r '.notificationHubName.value')
CURATED_HUB_NAME=$(echo "$outputs" | jq -r '.curatedHubName.value')
CAPTURE_CONSUMER_GROUP=$(echo "$outputs" | jq -r '.captureConsumerGroup.value')
STORAGE_ACCOUNT_NAME=$(echo "$outputs" | jq -r '.storageAccountName.value')
CAPTURE_CONTAINER_NAME=$(echo "$outputs" | jq -r '.captureContainerName.value')
SYSTEM_TOPIC_NAME=$(echo "$outputs" | jq -r '.systemTopicName.value')
SUBSCRIPTION_NAME=$(echo "$outputs" | jq -r '.eventSubscriptionName.value')
FUNCTION_APP_NAME=$(echo "$outputs" | jq -r '.functionAppName.value')
TEMPERATURE_LIMIT=$(echo "$outputs" | jq -r '.temperatureLimit.value')

[[ -n "$FUNCTION_APP_NAME" && "$FUNCTION_APP_NAME" != "null" ]] || fail "could not read the deployment outputs"
echo "Namespace:    $EVENTHUB_NAMESPACE_NAME"
echo "Function App: $FUNCTION_APP_NAME"
echo "System topic: $SYSTEM_TOPIC_NAME -> $SUBSCRIPTION_NAME"

# -----------------------------------------------------------------------------
echo ""
echo "=== Wiring the connection strings ==="
# -----------------------------------------------------------------------------
# Done here rather than in the template: connection strings are built from keys that only exist
# once the resources do, and anything a template emits as an output is kept in the deployment
# history. Reading them with the CLI keeps the secrets out of both.
STORAGE_KEY=$(az storage account keys list --account-name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query "[0].value" -o tsv --only-show-errors)
STORAGE_BLOB=$(az storage account show -n "$STORAGE_ACCOUNT_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query primaryEndpoints.blob -o tsv --only-show-errors)
STORAGE_QUEUE=$(az storage account show -n "$STORAGE_ACCOUNT_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query primaryEndpoints.queue -o tsv --only-show-errors)
STORAGE_TABLE=$(az storage account show -n "$STORAGE_ACCOUNT_NAME" -g "$RESOURCE_GROUP_NAME" \
	--query primaryEndpoints.table -o tsv --only-show-errors)
# Explicit endpoints, not EndpointSuffix: the Functions host cannot parse a suffix with a port.
STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_KEY};BlobEndpoint=${STORAGE_BLOB};QueueEndpoint=${STORAGE_QUEUE};TableEndpoint=${STORAGE_TABLE}"

SEND_CONNECTION=$(az eventhubs eventhub authorization-rule keys list --name telemetry-send \
	--eventhub-name "$TELEMETRY_HUB_NAME" --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query primaryConnectionString -o tsv --only-show-errors)
LISTEN_CONNECTION=$(az eventhubs namespace authorization-rule keys list --name pipeline-listen \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query primaryConnectionString -o tsv --only-show-errors)
# Namespace-level for the bindings: an entity-level string carries EntityPath, which would pin the
# output binding to the notifications hub instead of the curated one.
NAMESPACE_CONNECTION=$(az eventhubs namespace authorization-rule keys list \
	--name RootManageSharedAccessKey --namespace-name "$EVENTHUB_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" --query primaryConnectionString -o tsv --only-show-errors)

[[ -n "$SEND_CONNECTION" ]] || fail "could not read the send connection string"
[[ -n "$LISTEN_CONNECTION" ]] || fail "could not read the listen connection string"
[[ -n "$NAMESPACE_CONNECTION" ]] || fail "could not read the namespace connection string"

az functionapp config appsettings set --name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--settings \
	"AzureWebJobsStorage=$STORAGE_CONNECTION_STRING" \
	"WEBSITE_CONTENTAZUREFILECONNECTIONSTRING=$STORAGE_CONNECTION_STRING" \
	"STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING" \
	"EVENTHUB_NOTIFICATION_CONNECTION=$NAMESPACE_CONNECTION" \
	"EVENTHUB_CURATED_CONNECTION=$NAMESPACE_CONNECTION" \
	"ENABLE_ORYX_BUILD=true" \
	"SCM_DO_BUILD_DURING_DEPLOYMENT=true" \
	--only-show-errors 1>/dev/null || fail "could not set the function app settings"
echo "Configured the processor."

# -----------------------------------------------------------------------------
echo ""
echo "=== Publishing the application code ==="
# -----------------------------------------------------------------------------
cd "$SRC_DIR/functions" || fail "missing src/functions"
rm -f "$CURRENT_DIR/$FUNCTION_ZIP"
zip -r "$CURRENT_DIR/$FUNCTION_ZIP" function_app.py host.json requirements.txt 1>/dev/null
cd "$CURRENT_DIR" || exit 1

echo "Deploying the capture processor (the first run can take several minutes)..."
az functionapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--src-path "$FUNCTION_ZIP" \
	--type zip 1>/dev/null || fail "could not deploy the function app"
rm -f "$FUNCTION_ZIP"

# -----------------------------------------------------------------------------
echo ""
echo "=== Verifying the deployment ==="
# -----------------------------------------------------------------------------
az eventhubs eventhub show --name "$TELEMETRY_HUB_NAME" \
	--namespace-name "$EVENTHUB_NAMESPACE_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
	--query "{name:name, partitions:partitionCount, capture:captureDescription.enabled}" \
	--output table --only-show-errors || fail "the telemetry hub is not readable"

# Mirror scripts/deploy.sh so the demo runs after a Bicep deployment too.
cat >"$CURRENT_DIR/../scripts/.deployment-env" <<EOF
export RESOURCE_GROUP_NAME='$RESOURCE_GROUP_NAME'
export EVENTHUB_NAMESPACE_NAME='$EVENTHUB_NAMESPACE_NAME'
export TELEMETRY_HUB_NAME='$TELEMETRY_HUB_NAME'
export NOTIFICATION_HUB_NAME='$NOTIFICATION_HUB_NAME'
export CURATED_HUB_NAME='$CURATED_HUB_NAME'
export CAPTURE_CONSUMER_GROUP='$CAPTURE_CONSUMER_GROUP'
export CAPTURE_CONTAINER_NAME='$CAPTURE_CONTAINER_NAME'
export STORAGE_ACCOUNT_NAME='$STORAGE_ACCOUNT_NAME'
export SYSTEM_TOPIC_NAME='$SYSTEM_TOPIC_NAME'
export SUBSCRIPTION_NAME='$SUBSCRIPTION_NAME'
export FUNCTION_APP_NAME='$FUNCTION_APP_NAME'
export TEMPERATURE_LIMIT='$TEMPERATURE_LIMIT'
export EVENTHUB_SEND_CONNECTION_STRING='$SEND_CONNECTION'
export EVENTHUB_LISTEN_CONNECTION_STRING='$LISTEN_CONNECTION'
export EVENTHUB_NAMESPACE_CONNECTION_STRING='$NAMESPACE_CONNECTION'
export STORAGE_CONNECTION_STRING='$STORAGE_CONNECTION_STRING'
EOF

echo ""
echo "Deployment complete. Run 'bash ../scripts/validate.sh' to exercise every capability,"
echo "then 'bash ../scripts/run-pipeline.sh' for the end-to-end demo."
