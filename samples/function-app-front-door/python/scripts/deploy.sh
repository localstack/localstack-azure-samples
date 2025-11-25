#!/usr/bin/env bash
set -euo pipefail

# Deploy a minimal Python Azure Function App and configure Azure Front Door (AFD).
# What this script does, at a high level:
#   1) Parse inputs and set sane defaults
#   2) Generate unique, compliant resource names
#   3) Optionally enable LocalStack interception via azlocal (for emulator/testing)
#   4) Create a resource group and a storage account
#   5) Create a Linux Consumption (Functions v4) Function App running Python
#   6) Package and zip-deploy a simple HTTP-triggered function
#   7) Create AFD profile, endpoint, origin group, origin, and route
#   8) Print out URLs to test the function directly and via AFD
# Requirements: az CLI, bash, zip
# Optional: azlocal (LocalStack’s Azure interception helper) for emulator mode

# -------------------------------
# 1) Defaults (can be overridden via flags)
# -------------------------------
NAME_PREFIX="funcafd"       # Used as a base for naming resources
LOCATION="eastus"           # Azure region for resources
RESOURCE_GROUP=""           # If omitted, a unique name is generated
USE_LOCALSTACK="false"      # If true, try to intercept az calls using azlocal
PYTHON_VERSION="3.11"       # Python runtime used by the Function App

# -------------------------------
# 2) Usage / help text
# -------------------------------
print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -p, --name-prefix STR     Base name prefix (default: funcafd)
  -l, --location STR        Azure region (default: eastus)
  -g, --resource-group STR  Resource group name (auto-generated if omitted)
      --python-version STR  Python runtime version for Function App (default: 3.11)
      --use-localstack      Use azlocal interception for LocalStack emulator
  -h, --help                Show this help
EOF
}

# -------------------------------
# 3) Argument parsing
# -------------------------------
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

# -------------------------------
# 4) Paths to project assets
# -------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FUNCTION_SRC="$ROOT_DIR/function"  # Folder containing Function code (host.json, function.json, __init__.py)
ZIP_PATH="$ROOT_DIR/app.zip"       # Temporary zip for deployment

echo "Script directory path: "$SCRIPT_DIR
echo "Root directory path: "$ROOT_DIR
echo "Function code directory path: "$FUNCTION_SRC
echo "Zip deployment directory path: "$ZIP_PATH

# -------------------------------
# 5) Generate unique, compliant resource names
# -------------------------------
# Azure enforces specific constraints (e.g., storage account: lowercase alphanumeric, <=24 chars)
prefix=$(echo "$NAME_PREFIX" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
if [[ -z "$prefix" ]]; then prefix="demo"; fi
# Not cryptographically strong; just a short suffix to avoid collisions
suffix=$(printf "%05d" $(( (RANDOM % 100000) )))

if [[ -z "$RESOURCE_GROUP" ]]; then RESOURCE_GROUP="rg-$prefix-$suffix"; fi
storageName="st${prefix}${suffix}"
# storage account name: lower-case letters and numbers only, max length 24
storageName="${storageName:0:24}"
funcName="fa-$prefix-$suffix"          # Function App name
profileName="afd-$prefix-$suffix"      # AFD profile name
endpointName="ep-$prefix-$suffix"      # AFD endpoint name
originGroupName="og-$prefix"           # AFD origin group name
originName="or-$prefix"                # AFD origin name
routeName="rt-$prefix"                 # AFD route name

# -------------------------------
# 6) Optional LocalStack interception setup
#    If --use-localstack is passed and azlocal is available, route az CLI calls
#    to the LocalStack emulator. We ensure we end interception on exit.
# -------------------------------
INTERCEPTION_STARTED="false"
AZURE_CONFIG_DIR_CREATED="false"
finish() {
  # Always try to clean up transient resources on exit
  if [[ "$INTERCEPTION_STARTED" == "true" ]]; then
    if command -v azlocal >/dev/null 2>&1; then
      set +e
      azlocal stop_interception >/dev/null 2>&1 || true
      set -e
    fi
  fi
  # Remove temporary zip file if created
  if [[ -f "$ZIP_PATH" ]]; then rm -f "$ZIP_PATH"; fi
  # Remove temporary Azure CLI config dir if we created one
  if [[ "$AZURE_CONFIG_DIR_CREATED" == "true" && -n "${AZURE_CONFIG_DIR:-}" && -d "$AZURE_CONFIG_DIR" ]]; then
    rm -rf "$AZURE_CONFIG_DIR"
  fi
}
trap finish EXIT

if [[ "$USE_LOCALSTACK" == "true" ]]; then
  # Use an isolated Azure CLI config to avoid corrupt ~/.azure/clouds.config issues in emulator mode
  if command -v mktemp >/dev/null 2>&1; then
    AZ_TEMP_CONFIG_DIR="$(mktemp -d)"
  else
    # Fallback if mktemp is unavailable
    AZ_TEMP_CONFIG_DIR="$ROOT_DIR/.azlocal_config_$$"
    mkdir -p "$AZ_TEMP_CONFIG_DIR"
  fi
  export AZURE_CONFIG_DIR="$AZ_TEMP_CONFIG_DIR"
  AZURE_CONFIG_DIR_CREATED="true"
  echo "Using isolated AZURE_CONFIG_DIR at: $AZURE_CONFIG_DIR"

  if ! command -v azlocal >/dev/null 2>&1; then
    echo "Error: --use-localstack specified but 'azlocal' was not found in PATH. Install and configure azlocal (LocalStack Azure CLI helper) and ensure LocalStack is running." >&2
    exit 1
  fi
  if azlocal start_interception; then
    INTERCEPTION_STARTED="true"
    echo "LocalStack interception started."
  else
    echo "Error: azlocal failed to start interception. Ensure LocalStack is running and azlocal is configured correctly." >&2
    exit 1
  fi
fi

# -------------------------------
# 7) Show the resolved resource names (for visibility)
# -------------------------------
echo "Using names:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Storage Account: $storageName"
echo "  Function App:   $funcName"
echo "  AFD Profile:    $profileName"
echo "  AFD Endpoint:   $endpointName"
echo "  AFD OriginGrp:  $originGroupName"
echo "  AFD Origin:     $originName"
echo "  AFD Route:      $routeName"

# -------------------------------
# 8) Create Resource Group and Storage Account
# -------------------------------
# RG: logical container for all resources in this sample
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none
# Storage: Functions runtime requires a general-purpose storage account
az storage account create -g "$RESOURCE_GROUP" -n "$storageName" -l "$LOCATION" --sku Standard_LRS --kind StorageV2 -o none

# -------------------------------
# 9) Create the Function App (Linux Consumption, Python)
# -------------------------------
# --consumption-plan-location creates a serverless plan in the region
# --runtime/--runtime-version set the language and version
# --functions-version 4 pins the Functions runtime major version
# --os-type Linux deploys a Linux-based Function App
# --storage-account links the storage created above
az functionapp create \
  -g "$RESOURCE_GROUP" \
  -n "$funcName" \
  --consumption-plan-location "$LOCATION" \
  --runtime python \
  --runtime-version "$PYTHON_VERSION" \
  --functions-version 4 \
  --os-type Linux \
  --storage-account "$storageName" \
  --disable-app-insights -o none

# Ensure required app settings for reliable zip deployment on Linux Consumption
# - WEBSITE_RUN_FROM_PACKAGE=1: run the app from the deployed zip package
# - FUNCTIONS_WORKER_RUNTIME=python: explicitly set worker runtime
# - SCM_DO_BUILD_DURING_DEPLOYMENT=false: avoid Kudu build step (not needed for this minimal app)
if [[ "$USE_LOCALSTACK" != "true" ]]; then
  az functionapp config appsettings set \
    -g "$RESOURCE_GROUP" -n "$funcName" \
    --settings WEBSITE_RUN_FROM_PACKAGE=1 FUNCTIONS_WORKER_RUNTIME=python SCM_DO_BUILD_DURING_DEPLOYMENT=false -o none
else
  az functionapp config appsettings set \
    -g "$RESOURCE_GROUP" -n "$funcName" \
    --settings FUNCTIONS_WORKER_RUNTIME=python WEBSITE_RUN_FROM_PACKAGE=0 -o none
fi

# In LocalStack mode, also ensure the storage connection string is explicitly set, as
# automatic wiring may not be available in the emulator. We construct a standard
# Azure-style connection string using the first storage account key.
if [[ "$USE_LOCALSTACK" == "true" ]]; then
  STORAGE_KEY=$(az storage account keys list -g "$RESOURCE_GROUP" -n "$storageName" --query "[0].value" -o tsv)
  if [[ -z "$STORAGE_KEY" ]]; then
    echo "Failed to retrieve storage account key for $storageName" >&2
    exit 1
  fi
  # Construct a LocalStack-specific Storage connection string with explicit endpoints
  STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=$storageName;AccountKey=$STORAGE_KEY;BlobEndpoint=https://$storageName.blob.localhost.localstack.cloud:4566;QueueEndpoint=https://$storageName.queue.localhost.localstack.cloud:4566;TableEndpoint=https://$storageName.table.localhost.localstack.cloud:4566;FileEndpoint=https://$storageName.file.localhost.localstack.cloud:4566"
  az functionapp config appsettings set \
    -g "$RESOURCE_GROUP" -n "$funcName" \
    --settings AzureWebJobsStorage="$STORAGE_CONNECTION_STRING" WEBSITE_CONTENTAZUREFILECONNECTIONSTRING="$STORAGE_CONNECTION_STRING" SCM_RUN_FROM_PACKAGE= -o none
fi

# -------------------------------
# 10) Package and publish the Function code
# -------------------------------
# For real Azure, use zip deploy via Kudu. In LocalStack emulator mode, use

# funclocal to publish, as Kudu endpoints (azurewebsites.net) are not resolvable.
if [[ ! -d "$FUNCTION_SRC" ]]; then
  echo "Function source folder not found: $FUNCTION_SRC" >&2
  exit 1
fi

if [[ "$USE_LOCALSTACK" == "true" ]]; then
  # In emulator mode we publish via Azure Functions Core Tools (func) wrapped by funclocal.
  # Both tools must be available; fail fast with actionable guidance if not.
  if ! command -v funclocal >/dev/null 2>&1; then
    echo "Error: funclocal is required when using --use-localstack to publish the function app. Please ensure it is installed and in PATH." >&2
    echo "Hint: pip install azlocal (part of LocalStack Pro Azure tooling) and ensure LocalStack is running." >&2
    exit 1
  fi
  if ! command -v func >/dev/null 2>&1; then
    echo "Error: Azure Functions Core Tools ('func') not found in PATH." >&2
    echo "Install Functions Core Tools v4 and ensure 'func' is reachable. Examples:" >&2
    echo "  - npm i -g azure-functions-core-tools@4 --unsafe-perm true" >&2
    echo "  - See: https://learn.microsoft.com/azure/azure-functions/functions-run-local#install-the-azure-functions-core-tools" >&2
    echo "After installation, verify: func --version" >&2
    exit 1
  fi
  pushd "$FUNCTION_SRC" >/dev/null
  funclocal azure functionapp publish "$funcName" --python --build local --verbose --debug
  popd >/dev/null
else
  rm -f "$ZIP_PATH"
  ( cd "$FUNCTION_SRC" && zip -rq "$ZIP_PATH" . )
  az functionapp deployment source config-zip -g "$RESOURCE_GROUP" -n "$funcName" --src "$ZIP_PATH"
fi

# -------------------------------
# 11) Obtain the Function App default hostname and craft a test URL
# -------------------------------
funcHost=$(az functionapp show -g "$RESOURCE_GROUP" -n "$funcName" --query defaultHostName -o tsv)
if [[ -z "$funcHost" ]]; then
  echo "Could not resolve function defaultHostName" >&2
  exit 1
fi
# Build test URLs. In LocalStack, use local-friendly hostnames that route through the emulator.
if [[ "$USE_LOCALSTACK" == "true" ]]; then
  functionLocalHost="${funcName}website.localhost.localstack.cloud:4566"
  functionTestUrl="https://${functionLocalHost}/john"
  # Also expose an Azure-hostname variant bound to the edge port. Note: DNS will still resolve to Azure by default.
  # Use curl --resolve to map <host>:4566 to 127.0.0.1 for the request.
  functionAzureHostPort="${funcHost}:4566"
  functionTestAzureHostUrl="https://${functionAzureHostPort}/john"
  afdLocalHost="${endpointName}.afd.localhost.localstack.cloud:4566"
  afdTestUrl="https://${afdLocalHost}/john"
else
  functionTestUrl="https://$funcHost/john"
fi

# -------------------------------
# 12) Provision Azure Front Door (AFD) resources
# -------------------------------
# We keep arguments minimal, focusing on required and relevant parameters only.
# - Profile: the top-level AFD resource (Standard SKU)
# - Endpoint: the public entry point
# - Origin Group: contains health probe configuration
# - Origin: points to the Function App host
# - Route: maps incoming paths to the origin group with HTTPS redirect
az afd profile create -g "$RESOURCE_GROUP" --profile-name "$profileName" --sku Standard_AzureFrontDoor -o none
az afd endpoint create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --enabled-state Enabled -o none
az afd origin-group create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$originGroupName" --probe-request-type GET --probe-protocol Http --probe-interval-in-seconds 120 --probe-path / --sample-size 4 --successful-samples-required 3 --additional-latency-in-milliseconds 0 -o none
az afd origin create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$originGroupName" --origin-name "$originName" --host-name "$funcHost" --origin-host-header "$funcHost" --http-port 80 --https-port 443 -o none
az afd route create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --route-name "$routeName" --origin-group "$originGroupName" --patterns-to-match '/*' --https-redirect Enabled --supported-protocols Http Https --link-to-default-domain Enabled --forwarding-protocol MatchRequest -o none

# Grab the AFD endpoint hostname for the output (may not be immediately ready)
afdHost=$(az afd endpoint show -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --query hostName -o tsv || true)

# -------------------------------
# 13) Print summary and test URLs
# -------------------------------
echo
echo
echo "Deployment complete."
echo "Resource Group: $RESOURCE_GROUP"
if [[ "$USE_LOCALSTACK" == "true" ]]; then
  echo "Function Host (Azure-reported):  $funcHost"
  echo "Function Local Host:            ${functionLocalHost:-N/A}"
  echo "Test Function (local):          $functionTestUrl"
  echo "Function Azure Host (edge):     ${functionAzureHostPort}"
  echo "Test Function (azure host):     ${functionTestAzureHostUrl}"
else
  echo "Function Host:  $funcHost"
  echo "Test Function:  $functionTestUrl"
fi
if [[ -n "$afdHost" ]]; then
  echo "AFD Endpoint (Azure-reported):  $afdHost"
  if [[ "$USE_LOCALSTACK" == "true" ]]; then
    echo "AFD Local Endpoint:             ${afdLocalHost:-$endpointName.afd.localhost.localstack.cloud}"
    echo "Test via AFD (local):           ${afdTestUrl:-https://$endpointName.afd.localhost.localstack.cloud/john}"
  else
    echo "Test via AFD:  https://$afdHost/john"
  fi
fi