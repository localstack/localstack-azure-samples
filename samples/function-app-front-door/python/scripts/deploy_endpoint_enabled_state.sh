#!/usr/bin/env bash
set -euo pipefail

# Deploy a Python Function App and Azure Front Door (AFD), then validate
# the Endpoint enabled/disabled behavior in the LocalStack Azure emulator or real Azure.
#
# What this script validates:
#  - When the AFD endpoint is Enabled, requests are served (expect 2xx).
#  - After updating the endpoint to Disabled, requests return a 4xx (e.g., 403).
#  - Re-enabling restores normal behavior (2xx again).
#
# Requirements: az CLI, curl
# Optional for LocalStack mode: azlocal (LocalStack Azure CLI interceptor), funclocal + func (Functions Core Tools)
#
# Usage examples:
#  ./deploy_endpoint_enabled_state.sh --use-localstack
#  ./deploy_endpoint_enabled_state.sh --name-prefix afdtest --location eastus
#

# -------------------------------
# Defaults (overridable by flags)
# -------------------------------
NAME_PREFIX="afdstate"
LOCATION="eastus"
RESOURCE_GROUP=""
USE_LOCALSTACK="false"
PYTHON_VERSION="3.11"

# -------------------------------
# Parse arguments
# -------------------------------
print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -p, --name-prefix STR     Base name prefix (default: afdstate)
  -l, --location STR        Azure region (default: eastus)
  -g, --resource-group STR  Resource group name (auto-generated if omitted)
      --python-version STR  Python runtime for Function App (default: 3.11)
      --use-localstack      Use azlocal interception for LocalStack emulator
  -h, --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--name-prefix) NAME_PREFIX=${2:-}; shift 2;;
    -l|--location) LOCATION=${2:-}; shift 2;;
    -g|--resource-group) RESOURCE_GROUP=${2:-}; shift 2;;
    --python-version) PYTHON_VERSION=${2:-}; shift 2;;
    --use-localstack) USE_LOCALSTACK="true"; shift;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown option: $1" >&2; print_usage; exit 1;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FUNCTION_SRC="$ROOT_DIR/function"
ENV_OUT="$SCRIPT_DIR/.last_deploy_endpoint_enabled_state.env"

# -------------------------------
# Name generation
# -------------------------------
prefix=$(echo "$NAME_PREFIX" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
[[ -z "$prefix" ]] && prefix="demo"
suffix=$(printf "%05d" $(( (RANDOM % 100000) )))

[[ -z "$RESOURCE_GROUP" ]] && RESOURCE_GROUP="rg-$prefix-$suffix"
storageName="st${prefix}${suffix}"; storageName="${storageName:0:24}"
funcName="fa-$prefix-$suffix"
profileName="afd-$prefix-$suffix"
endpointName="ep-$prefix-$suffix"
originGroupName="og-$prefix"
originName="or-$prefix"
routeName="rt-$prefix"

# -------------------------------
# Optional LocalStack interception
# -------------------------------
INTERCEPTION_STARTED="false"
AZURE_CONFIG_DIR_CREATED="false"
finish() {
  if [[ "$INTERCEPTION_STARTED" == "true" ]] && command -v azlocal >/dev/null 2>&1; then
    set +e; azlocal stop_interception >/dev/null 2>&1 || true; set -e
  fi
  if [[ -f "$ENV_OUT" ]]; then echo "Deployment env saved at: $ENV_OUT"; fi
  if [[ "$AZURE_CONFIG_DIR_CREATED" == "true" && -n "${AZURE_CONFIG_DIR:-}" && -d "$AZURE_CONFIG_DIR" ]]; then
    rm -rf "$AZURE_CONFIG_DIR"
  fi
}
trap finish EXIT

if [[ "$USE_LOCALSTACK" == "true" ]]; then
  if command -v mktemp >/dev/null 2>&1; then AZ_TEMP_CONFIG_DIR="$(mktemp -d)"; else AZ_TEMP_CONFIG_DIR="$(pwd)/.azlocal_config_$$"; mkdir -p "$AZ_TEMP_CONFIG_DIR"; fi
  export AZURE_CONFIG_DIR="$AZ_TEMP_CONFIG_DIR"; AZURE_CONFIG_DIR_CREATED="true"
  echo "Using isolated AZURE_CONFIG_DIR at: $AZURE_CONFIG_DIR"
  if ! command -v azlocal >/dev/null 2>&1; then
    echo "Error: --use-localstack specified but 'azlocal' not found in PATH." >&2
    exit 1
  fi
  azlocal start_interception && INTERCEPTION_STARTED="true" || { echo "Failed to start azlocal interception" >&2; exit 1; }
fi

# -------------------------------
# Resource group + storage + function app
# -------------------------------
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none
az storage account create -g "$RESOURCE_GROUP" -n "$storageName" -l "$LOCATION" --sku Standard_LRS -o none
az functionapp create -g "$RESOURCE_GROUP" -n "$funcName" \
  --storage-account "$storageName" --consumption-plan-location "$LOCATION" \
  --runtime python --functions-version 4 --os-type Linux --runtime-version "$PYTHON_VERSION" -o none

# In LocalStack mode, wire AzureWebJobsStorage explicitly and publish via funclocal
if [[ "$USE_LOCALSTACK" == "true" ]]; then
  if ! command -v funclocal >/dev/null 2>&1; then
    echo "Error: funclocal is required in --use-localstack mode." >&2
    exit 1
  fi
  if ! command -v func >/dev/null 2>&1; then
    echo "Error: Azure Functions Core Tools 'func' not found." >&2
    exit 1
  fi
  STORAGE_KEY=$(az storage account keys list -g "$RESOURCE_GROUP" -n "$storageName" --query "[0].value" -o tsv)
  STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=$storageName;AccountKey=$STORAGE_KEY;BlobEndpoint=https://$storageName.blob.localhost.localstack.cloud:4566;QueueEndpoint=https://$storageName.queue.localhost.localstack.cloud:4566;TableEndpoint=https://$storageName.table.localhost.localstack.cloud:4566;FileEndpoint=https://$storageName.file.localhost.localstack.cloud:4566"
  az functionapp config appsettings set -g "$RESOURCE_GROUP" -n "$funcName" --settings AzureWebJobsStorage="$STORAGE_CONNECTION_STRING" -o none
  pushd "$FUNCTION_SRC" >/dev/null
  funclocal azure functionapp publish "$funcName" --python --build local --verbose
  popd >/dev/null
else
  # Zip deploy for real Azure
  ZIP_PATH="$ROOT_DIR/app.zip"
  rm -f "$ZIP_PATH"
  ( cd "$FUNCTION_SRC" && zip -rq "$ZIP_PATH" . )
  az functionapp deployment source config-zip -g "$RESOURCE_GROUP" -n "$funcName" --src "$ZIP_PATH"
fi

# Fetch function default hostname
funcHost=$(az functionapp show -g "$RESOURCE_GROUP" -n "$funcName" --query defaultHostName -o tsv)
if [[ -z "$funcHost" ]]; then echo "Could not resolve function defaultHostName" >&2; exit 1; fi

# -------------------------------
# AFD: profile, endpoint, origin group, origin, route
# -------------------------------
az afd profile create -g "$RESOURCE_GROUP" --profile-name "$profileName" --sku Standard_AzureFrontDoor -o none
az afd endpoint create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --enabled-state Enabled -o none
az afd origin-group create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$originGroupName" \
  --probe-request-type GET --probe-protocol Http --probe-interval-in-seconds 120 --probe-path / --sample-size 4 --successful-samples-required 3 --additional-latency-in-milliseconds 0 -o none
az afd origin create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$originGroupName" --origin-name "$originName" \
  --host-name "$funcHost" --origin-host-header "$funcHost" --http-port 80 --https-port 443 -o none
az afd route create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --route-name "$routeName" \
  --origin-group "$originGroupName" --patterns-to-match '/*' --https-redirect Enabled --supported-protocols Http Https \
  --link-to-default-domain Enabled --forwarding-protocol MatchRequest -o none

# Determine AFD host and test URL
afdHost=$(az afd endpoint show -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --query hostName -o tsv || true)
if [[ "$USE_LOCALSTACK" == "true" ]]; then
  afdLocalHost="${endpointName}.afd.localhost.localstack.cloud:4566"
  TEST_URL="https://${afdLocalHost}/john"
else
  TEST_URL="https://${afdHost}/john"
fi

# Helper to curl and return HTTP status code
http_status() {
  local url="$1"
  curl -ks -o /dev/null -w "%{http_code}" "$url"
}

# -------------------------------
# Tests: enabled -> disabled -> enabled
# -------------------------------
# Wait a little for routing to settle in emulator
sleep 1

code=$(http_status "$TEST_URL")
echo "Initial request status: $code ($TEST_URL)"
if [[ ! "$code" =~ ^2 ]]; then
  echo "Expected 2xx when endpoint is Enabled, got: $code" >&2
  exit 1
fi

# Disable the endpoint
az afd endpoint update -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --enabled-state Disabled -o none
sleep 1
code=$(http_status "$TEST_URL")
echo "After disable status: $code ($TEST_URL)"
if [[ "$code" =~ ^2 ]]; then
  echo "Expected non-2xx (4xx) when endpoint is Disabled, got: $code" >&2
  exit 1
fi

# Re-enable the endpoint
az afd endpoint update -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --enabled-state Enabled -o none
sleep 1
code=$(http_status "$TEST_URL")
echo "After re-enable status: $code ($TEST_URL)"
if [[ ! "$code" =~ ^2 ]]; then
  echo "Expected 2xx after re-enabling endpoint, got: $code" >&2
  exit 1
fi

# Summary
echo
echo "Validation complete. Endpoint enabled/disabled behavior works as expected."
echo "Resource Group: $RESOURCE_GROUP"
echo "AFD Test URL:   $TEST_URL"
echo "Env file:       $ENV_OUT"
