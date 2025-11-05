#!/usr/bin/env bash
set -euo pipefail

# Purpose
# -------
# Minimal deployment to validate AFD Route specificity/precedence (11.3) using the simplest topology:
#   - One Function App (single backend)
#   - One AFD Origin Group
#   - Two AFD Routes bound to the same endpoint and origin group:
#       • R1 (catch‑all): patterns ['/*']
#       • R2 (specific): patterns ['/john']
#     The data plane should choose the most specific matching route for a given request path.
#

# -------------------------------
# Defaults (overridable via flags)
# -------------------------------
NAME_PREFIX="funcafd11_3"
LOCATION="eastus"
RESOURCE_GROUP=""
USE_LOCALSTACK="false"
PYTHON_VERSION="3.11"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -p, --name-prefix STR     Base name prefix (default: funcafd11_3)
  -l, --location STR        Azure region (default: eastus)
  -g, --resource-group STR  Resource group name (auto-generated if omitted)
      --python-version STR  Python runtime version for Function App (default: 3.11)
      --use-localstack      Use azlocal/funclocal for LocalStack emulator
  -h, --help                Show this help
EOF
}

# -------------------------------
# Parse arguments
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
# Paths
# -------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FUNCTION_SRC="$ROOT_DIR/function"
ZIP_PATH="$ROOT_DIR/app_single.zip"

# -------------------------------
# Name generation (unique, compliant)
# -------------------------------
prefix=$(echo "$NAME_PREFIX" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
if [[ -z "$prefix" ]]; then prefix="demo"; fi
suffix=$(printf "%05d" $(((RANDOM % 100000))))

if [[ -z "$RESOURCE_GROUP" ]]; then RESOURCE_GROUP="rg-$prefix-$suffix"; fi
storageName="st${prefix}${suffix}"; storageName="${storageName:0:24}"
funcName="fa-$prefix-$suffix"
profileName="afd-$prefix-$suffix"
endpointName="ep-$prefix-$suffix"
originGroupName="og-$prefix"
originName="or-$prefix"
routeAllName="rt-${prefix}-all"
routeJohnName="rt-${prefix}-john"

# -------------------------------
# Optional LocalStack interception lifecycle
# -------------------------------
INTERCEPTION_STARTED="false"
AZURE_CONFIG_DIR_CREATED="false"
finish() {
  set +e
  if [[ -f "$ZIP_PATH" ]]; then rm -f "$ZIP_PATH"; fi
  if [[ "$INTERCEPTION_STARTED" == "true" ]] && command -v azlocal >/dev/null 2>&1; then
    azlocal stop_interception >/dev/null 2>&1 || true
  fi
  if [[ "$AZURE_CONFIG_DIR_CREATED" == "true" && -n "${AZURE_CONFIG_DIR:-}" && -d "$AZURE_CONFIG_DIR" ]]; then
    rm -rf "$AZURE_CONFIG_DIR"
  fi
  set -e
}
trap finish EXIT

if [[ "$USE_LOCALSTACK" == "true" ]]; then
  if command -v mktemp >/dev/null 2>&1; then
    AZ_TEMP_CONFIG_DIR="$(mktemp -d)"
  else
    AZ_TEMP_CONFIG_DIR="$ROOT_DIR/.azlocal_config_$$"; mkdir -p "$AZ_TEMP_CONFIG_DIR"
  fi
  export AZURE_CONFIG_DIR="$AZ_TEMP_CONFIG_DIR"; AZURE_CONFIG_DIR_CREATED="true"
  echo "Using isolated AZURE_CONFIG_DIR: $AZURE_CONFIG_DIR"
  if ! command -v azlocal >/dev/null 2>&1; then
    echo "Error: --use-localstack specified but 'azlocal' not found in PATH." >&2
    exit 1
  fi
  if azlocal start_interception; then
    INTERCEPTION_STARTED="true"; echo "LocalStack interception started."
  else
    echo "Error: azlocal failed to start interception. Ensure LocalStack is running." >&2
    exit 1
  fi
fi

# -------------------------------
# Echo plan
# -------------------------------
cat <<EOP
Using names:
  Resource Group: $RESOURCE_GROUP
  Storage:        $storageName
  Function App:   $funcName
  AFD Profile:    $profileName
  AFD Endpoint:   $endpointName
  AFD OriginGrp:  $originGroupName
  AFD Origin:     $originName
  Route (all):    $routeAllName → patterns ['/*']
  Route (john):   $routeJohnName → patterns ['/john']

Test goal:
  - Requests to '/john' should match the specific route.
  - Requests to any other path should match the catch‑all route.
  - Both routes point to the same origin group and origin (single Function backend).
EOP

# -------------------------------
# Create RG and storage
# -------------------------------
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none
az storage account create -g "$RESOURCE_GROUP" -n "$storageName" -l "$LOCATION" --sku Standard_LRS --kind StorageV2 -o none

# -------------------------------
# Create the Function App (Linux Consumption, Python)
# -------------------------------
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

# App settings
if [[ "$USE_LOCALSTACK" != "true" ]]; then
  az functionapp config appsettings set \
    -g "$RESOURCE_GROUP" -n "$funcName" \
    --settings WEBSITE_RUN_FROM_PACKAGE=1 FUNCTIONS_WORKER_RUNTIME=python SCM_DO_BUILD_DURING_DEPLOYMENT=false -o none
else
  az functionapp config appsettings set \
    -g "$RESOURCE_GROUP" -n "$funcName" \
    --settings FUNCTIONS_WORKER_RUNTIME=python WEBSITE_RUN_FROM_PACKAGE=0 -o none
  # Explicit storage connection string for emulator mode
  STORAGE_KEY=$(az storage account keys list -g "$RESOURCE_GROUP" -n "$storageName" --query "[0].value" -o tsv)
  if [[ -z "$STORAGE_KEY" ]]; then echo "Failed to get storage key" >&2; exit 1; fi
  STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=$storageName;AccountKey=$STORAGE_KEY;BlobEndpoint=https://$storageName.blob.localhost.localstack.cloud:4566;QueueEndpoint=https://$storageName.queue.localhost.localstack.cloud:4566;TableEndpoint=https://$storageName.table.localhost.localstack.cloud:4566;FileEndpoint=https://$storageName.file.localhost.localstack.cloud:4566"
  az functionapp config appsettings set \
    -g "$RESOURCE_GROUP" -n "$funcName" \
    --settings AzureWebJobsStorage="$STORAGE_CONNECTION_STRING" WEBSITE_CONTENTAZUREFILECONNECTIONSTRING="$STORAGE_CONNECTION_STRING" SCM_RUN_FROM_PACKAGE= -o none
fi

# -------------------------------
# Deploy function code
# -------------------------------
if [[ ! -d "$FUNCTION_SRC" ]]; then
  echo "Function source folder not found: $FUNCTION_SRC" >&2
  exit 1
fi

if [[ "$USE_LOCALSTACK" == "true" ]]; then
  if ! command -v funclocal >/dev/null 2>&1; then
    echo "Error: funclocal is required in --use-localstack mode." >&2
    exit 1
  fi
  if ! command -v func >/dev/null 2>&1; then
    echo "Error: Azure Functions Core Tools ('func') not found in PATH." >&2
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
# Resolve function host and craft test URLs
# -------------------------------
funcHost=$(az functionapp show -g "$RESOURCE_GROUP" -n "$funcName" --query defaultHostName -o tsv)
if [[ -z "$funcHost" ]]; then echo "Could not resolve function defaultHostName" >&2; exit 1; fi

if [[ "$USE_LOCALSTACK" == "true" ]]; then
  functionLocalHost="${funcName}website.localhost.localstack.cloud:4566"
  testFuncUrl="https://${functionLocalHost}/john"
  afdLocalHost="${endpointName}.afd.localhost.localstack.cloud:4566"
  afdTestJohn="https://${afdLocalHost}/john"
  afdTestOther="https://${afdLocalHost}/anythingelse"
else
  testFuncUrl="https://$funcHost/john"
fi

# -------------------------------
# Provision AFD: profile, endpoint, origin group, origin, two routes
# -------------------------------
az afd profile create -g "$RESOURCE_GROUP" --profile-name "$profileName" --sku Standard_AzureFrontDoor -o none
az afd endpoint create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --enabled-state Enabled -o none

# Origin group with basic probe config
az afd origin-group create \
  -g "$RESOURCE_GROUP" \
  --profile-name "$profileName" \
  --origin-group-name "$originGroupName" \
  --probe-request-type HEAD \
  --probe-protocol Http \
  --probe-interval-in-seconds 120 \
  --probe-path / -o none

# Single origin pointing to the single Function host
az afd origin create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$originGroupName" \
  --origin-name "$originName" --host-name "$funcHost" --origin-host-header "$funcHost" \
  --http-port 80 --https-port 443 -o none

# Two routes on the same endpoint and origin group
# R1: catch‑all
az afd route create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" \
  --route-name "$routeAllName" --origin-group "$originGroupName" \
  --patterns-to-match '/*' \
  --https-redirect Enabled --supported-protocols Http Https \
  --link-to-default-domain Enabled --forwarding-protocol MatchRequest -o none

# R2: specific
az afd route create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" \
  --route-name "$routeJohnName" --origin-group "$originGroupName" \
  --patterns-to-match '/john' \
  --https-redirect Enabled --supported-protocols Http Https \
  --link-to-default-domain Enabled --forwarding-protocol MatchRequest -o none

# Endpoint host (may not be instantly ready)
afdHost=$(az afd endpoint show -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --query hostName -o tsv || true)

# -------------------------------
# Summary and test hints
# -------------------------------
echo
echo "Deployment complete."
echo "Resource Group: $RESOURCE_GROUP"
echo "Function Host: $funcHost"
if [[ "$USE_LOCALSTACK" == "true" ]]; then
  echo "Test Function (local): $testFuncUrl"
  echo "AFD Local Endpoint: ${afdLocalHost}"
  echo "Test via AFD (local, specific): $afdTestJohn"
  echo "Test via AFD (local, other):   $afdTestOther"
else
  if [[ -n "$afdHost" ]]; then
    echo "AFD Endpoint: $afdHost"
    echo "Test via AFD (specific): https://$afdHost/john"
    echo "Test via AFD (other):    https://$afdHost/anythingelse"
  fi
fi

cat <<'EON'

Verification:
- Specificity: '/john' should be handled by the route with pattern '/john'; any other path by '/*'.
- Since both routes point to the same backend, responses may look identical. To observe route choice:
  • Enable LocalStack debug logs and watch for lines like:
      [AFD] Using route ... selected_pattern='/john'
    vs:
      [AFD] Using route ... selected_pattern='/*'
  • Alternatively, change your function to echo the request path or add a simple tag so outputs differ.

PowerShell quick checks (LocalStack):
  curl.exe -sk https://<endpoint>.afd.localhost.localstack.cloud:4566/john
  curl.exe -sk https://<endpoint>.afd.localhost.localstack.cloud:4566/anythingelse

Cleanup:
  Use the existing cleanup script. Example:
    bash ./scripts/cleanup_routes_specificity.sh --resource-group <rg> --use-localstack
EON
