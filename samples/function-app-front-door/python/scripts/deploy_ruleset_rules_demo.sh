#!/usr/bin/env bash
set -euo pipefail

# Demo: Azure Front Door RuleSet/Rules data plane in LocalStack emulator
# - Deploys a Python Function App (HTTP trigger)
# - Creates AFD Profile, Endpoint, Origin Group, Origin, and a Route
# - Creates a Rule Set with three common rules and attaches it to the Route:
#     1) ModifyResponseHeader: when RequestMethod == GET, set X-CDN: MSFT
#     2) UrlRewrite: when UrlPath begins with /api, rewrite path to /
#     3) UrlRedirect: when UrlPath begins with /old, 302 redirect to /new
#
# Requirements: az CLI, zip. Optional: azlocal for LocalStack interception.

# -------------------------------
# Defaults (override via flags)
# -------------------------------
NAME_PREFIX="funcafd-rules"
LOCATION="eastus"
RESOURCE_GROUP=""
USE_LOCALSTACK="false"
PYTHON_VERSION="3.11"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -p, --name-prefix STR     Base name prefix (default: funcafd-rules)
  -l, --location STR        Azure region (default: eastus)
  -g, --resource-group STR  Resource group name (auto-generated if omitted)
      --python-version STR  Python runtime version (default: 3.11)
      --use-localstack      Use azlocal interception for LocalStack emulator
  -h, --help                Show this help
EOF
}

# Parse args
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

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FUNCTION_SRC="$ROOT_DIR/function"
ZIP_PATH="$ROOT_DIR/app_rules.zip"

# Name generation
prefix=$(echo "$NAME_PREFIX" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
[[ -z "$prefix" ]] && prefix="demo"
suffix=$(printf "%05d" $(((RANDOM % 100000))))

[[ -z "$RESOURCE_GROUP" ]] && RESOURCE_GROUP="rg-$prefix-$suffix"
storageName="st${prefix}${suffix}"; storageName="${storageName:0:24}"
funcName="fa-$prefix-$suffix"
profileName="afd-$prefix-$suffix"
endpointName="ep-$prefix-$suffix"
originGroupName="og-$prefix"
originName="or-$prefix"
routeName="rt-$prefix"
rulesetName="rs$prefix"

# Interception lifecycle (optional)
INTERCEPTION_STARTED="false"
AZURE_CONFIG_DIR_CREATED="false"
finish() {
  set +e
  [[ -f "$ZIP_PATH" ]] && rm -f "$ZIP_PATH"
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
  if command -v mktemp >/dev/null 2>&1; then AZ_TEMP_CONFIG_DIR="$(mktemp -d)"; else AZ_TEMP_CONFIG_DIR="$ROOT_DIR/.azlocal_config_$$"; mkdir -p "$AZ_TEMP_CONFIG_DIR"; fi
  export AZURE_CONFIG_DIR="$AZ_TEMP_CONFIG_DIR"; AZURE_CONFIG_DIR_CREATED="true"
  echo "Using isolated AZURE_CONFIG_DIR: $AZURE_CONFIG_DIR"
  if ! command -v azlocal >/dev/null 2>&1; then
    echo "Error: --use-localstack specified but 'azlocal' not found in PATH." >&2
    exit 1
  fi
  if azlocal start_interception; then INTERCEPTION_STARTED="true"; echo "LocalStack interception started."; else echo "Error: azlocal failed to start interception." >&2; exit 1; fi
fi

# 1) Resource group and storage
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none
az storage account create -g "$RESOURCE_GROUP" -n "$storageName" -l "$LOCATION" --sku Standard_LRS --kind StorageV2 -o none

# 2) Function App (Linux Consumption)
# Note: Python Functions on Consumption are supported on Linux. Force OS to Linux to avoid
# "Runtime python not supported for os windows" on Windows/WSL hosts.
az functionapp create \
  -g "$RESOURCE_GROUP" -n "$funcName" \
  --consumption-plan-location "$LOCATION" \
  --runtime python \
  --runtime-version "$PYTHON_VERSION" \
  --functions-version 4 \
  --os-type Linux \
  --storage-account "$storageName" \
  --disable-app-insights -o none

# App settings to ensure reliable deployment behavior
if [[ "$USE_LOCALSTACK" != "true" ]]; then
  az functionapp config appsettings set \
    -g "$RESOURCE_GROUP" -n "$funcName" \
    --settings WEBSITE_RUN_FROM_PACKAGE=1 FUNCTIONS_WORKER_RUNTIME=python SCM_DO_BUILD_DURING_DEPLOYMENT=false -o none
else
  az functionapp config appsettings set \
    -g "$RESOURCE_GROUP" -n "$funcName" \
    --settings FUNCTIONS_WORKER_RUNTIME=python WEBSITE_RUN_FROM_PACKAGE=0 -o none
  # Explicit storage connection string for emulator mode (LocalStack)
  STORAGE_KEY=$(az storage account keys list -g "$RESOURCE_GROUP" -n "$storageName" --query "[0].value" -o tsv)
  if [[ -z "$STORAGE_KEY" ]]; then
    echo "Failed to retrieve storage account key for $storageName" >&2
    exit 1
  fi
  STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=$storageName;AccountKey=$STORAGE_KEY;BlobEndpoint=https://$storageName.blob.localhost.localstack.cloud:4566;QueueEndpoint=https://$storageName.queue.localhost.localstack.cloud:4566;TableEndpoint=https://$storageName.table.localhost.localstack.cloud:4566;FileEndpoint=https://$storageName.file.localhost.localstack.cloud:4566"
  az functionapp config appsettings set \
    -g "$RESOURCE_GROUP" -n "$funcName" \
    --settings AzureWebJobsStorage="$STORAGE_CONNECTION_STRING" WEBSITE_CONTENTAZUREFILECONNECTIONSTRING="$STORAGE_CONNECTION_STRING" SCM_RUN_FROM_PACKAGE= -o none
fi

# 3) Deploy the simple HTTP function
if [[ ! -d "$FUNCTION_SRC" ]]; then
  echo "Function source folder not found: $FUNCTION_SRC" >&2
  exit 1
fi

if [[ "$USE_LOCALSTACK" == "true" ]]; then
  # In emulator mode publish via funclocal + Azure Functions Core Tools
  if ! command -v funclocal >/dev/null 2>&1; then
    echo "Error: funclocal is required when using --use-localstack to publish the function app." >&2
    echo "Hint: pip install azlocal (LocalStack tooling) and ensure LocalStack is running." >&2
    exit 1
  fi
  if ! command -v func >/dev/null 2>&1; then
    echo "Error: Azure Functions Core Tools ('func') not found in PATH." >&2
    echo "Install Functions Core Tools v4 and ensure 'func' is reachable (func --version)." >&2
    exit 1
  fi
  pushd "$FUNCTION_SRC" >/dev/null
  funclocal azure functionapp publish "$funcName" --python --build local --verbose --debug
  popd >/dev/null
else
  rm -f "$ZIP_PATH"
  ( cd "$FUNCTION_SRC" && zip -rq "$ZIP_PATH" . )
  az functionapp deployment source config-zip -g "$RESOURCE_GROUP" -n "$funcName" --src "$ZIP_PATH" -o none
fi

funcHost=$(az functionapp show -g "$RESOURCE_GROUP" -n "$funcName" --query "defaultHostName" -o tsv)

# 4) AFD profile + endpoint
az afd profile create -g "$RESOURCE_GROUP" --profile-name "$profileName" --sku Standard_AzureFrontDoor 1>/dev/null
# Important: pass an enabled state so the request includes endpoint.properties (required by the emulator)
az afd endpoint create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --enabled-state Enabled 1>/dev/null
echo "profile and endpoint created"
epHost=$(az afd endpoint show -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --query "hostName" -o tsv)

# 5) Origin group + origin pointing to the Function App host
az afd origin-group create \
  -g "$RESOURCE_GROUP" \
  --profile-name "$profileName" \
  --origin-group-name "$originGroupName" \
  --enable-health-probe \
  --probe-request-type HEAD \
  --probe-protocol Http \
  --probe-interval-in-seconds 120 \
  --probe-path / \
  --sample-size 4 \
  --successful-samples-required 3 -o none
echo "origin group created (health probe enabled: HEAD Http / every 120s)"
az afd origin create -g "$RESOURCE_GROUP" --profile-name "$profileName" \
  --origin-group-name "$originGroupName" --origin-name "$originName" \
  --host-name "$funcHost" --http-port 80 --https-port 443 --origin-host-header "$funcHost" 1>/dev/null
echo "origin created"
# 6) Rule Set + three rules
az afd rule-set create -g "$RESOURCE_GROUP" --profile-name "$profileName" --rule-set-name "$rulesetName" -o none
echo "rule-set created"
# Rule 1: ModifyResponseHeader when RequestMethod == GET
# Using CLI flags instead of JSON --conditions/--actions (unsupported for az afd rule create)
az afd rule create \
  -g "$RESOURCE_GROUP" \
  --profile-name "$profileName" \
  --rule-set-name "$rulesetName" \
  --rule-name rule1 \
  --order 1 \
  --match-variable RequestMethod \
  --operator Equal \
  --match-values GET \
  --negate-condition false \
  --match-processing-behavior Continue \
  --action-name ModifyResponseHeader \
  --header-action Overwrite \
  --header-name X-CDN \
  --header-value MSFT -o none
echo "rule1 created"
# Rule 2: UrlRewrite when UrlPath begins with /api -> rewrite entire path to /
az afd rule create \
  -g "$RESOURCE_GROUP" \
  --profile-name "$profileName" \
  --rule-set-name "$rulesetName" \
  --rule-name rule2 \
  --order 2 \
  --match-variable UrlPath \
  --operator BeginsWith \
  --match-values /api \
  --negate-condition false \
  --match-processing-behavior Continue \
  --action-name UrlRewrite \
  --destination / -o none
echo "rule2 created"
# Rule 3: UrlRedirect when UrlPath begins with /old -> 302 Found to /new
az afd rule create \
  -g "$RESOURCE_GROUP" \
  --profile-name "$profileName" \
  --rule-set-name "$rulesetName" \
  --rule-name rule3 \
  --order 3 \
  --match-variable UrlPath \
  --operator BeginsWith \
  --match-values /old \
  --negate-condition false \
  --action-name UrlRedirect \
  --redirect-type Found \
  --destination /new -o none
echo "rule3 created"
# 7) Route with attached rule set
# Attach by NAME for maximum compatibility (CLI supports names here). Then explicitly update as a safety net.
az afd route create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" \
  --route-name "$routeName" --origin-group "$originGroupName" \
  --supported-protocols Http Https --forwarding-protocol MatchRequest \
  --patterns-to-match '/*' \
  --rule-sets "$rulesetName" 1>/dev/null
echo "route created (ruleset attached by name)"

# Safety re-attach (idempotent) in case of eventual consistency of the control plane
az afd route update -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" \
  --route-name "$routeName" --rule-sets "$rulesetName" -o none
echo "route updated to ensure ruleset attachment"
# Output
cat <<OUT

Deployment complete.

Function App host:   https://$funcHost
AFD Endpoint host:   https://$epHost

Try these commands (adjust scheme/ports if needed for LocalStack):

# 1) ModifyResponseHeader on GET
curl -i "https://${endpointName}.afd.localhost.localstack.cloud:4566/" | grep -i "^X-CDN:\s*MSFT" || echo "Header X-CDN not present"


# 2) UrlRewrite: /api -> /
curl -i "https://${endpointName}.afd.localhost.localstack.cloud:4566/api" | head -n 1

# 3) UrlRedirect: /old -> /new
curl -i -L "https://${endpointName}.afd.localhost.localstack.cloud:4566/old" | head -n 5

Cleanup:
  az group delete -n "$RESOURCE_GROUP" -y --no-wait
OUT
