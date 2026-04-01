#!/usr/bin/env bash
set -euo pipefail

# Unified deployment script for the Function App + Azure Front Door samples.
#
# This script provisions everything needed to exercise the following Azure Front Door data plane behaviors:
#   1) Basic single-origin routing (ep-basic)
#   2) Multiple origins with priority/weight selection (ep-multi)
#   3) Route specificity/precedence (ep-spec)
#   4) Rules Engine demo via Rule Set + Rule (ep-rules)
#   5) Endpoint enabled/disabled state toggle (ep-state)
#
# It supports deploying to real Azure or to LocalStack’s Azure emulator via azlocal interception.
# By default, all scenarios are deployed. You can selectively skip scenarios via flags.
#
# Requirements
#   - az CLI
#   - bash, zip
#   - Optional for LocalStack mode: azlocal (CLI interceptor), Azure Functions Core Tools ('func')
#
# Examples
#   # Real Azure (eastus by default)
#   bash ./scripts/deploy_all.sh --name-prefix demo
#
#   # LocalStack emulator
#   bash ./scripts/deploy_all.sh --name-prefix demo --use-localstack
#

# -------------------------------
# Defaults (overridable via flags)
# -------------------------------
NAME_PREFIX="funcafdall"
LOCATION="eastus"
RESOURCE_GROUP=""
USE_LOCALSTACK="false"
PYTHON_VERSION="3.11"

# Scenario toggles
DO_BASIC="true"
DO_MULTI="true"
DO_SPEC="true"
DO_RULES="true"
DO_STATE="true"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -p, --name-prefix STR       Base name prefix (default: funcafdall)
  -l, --location STR          Azure region (default: eastus)
  -g, --resource-group STR    Resource group name (auto-generated if omitted)
      --python-version STR    Python runtime for Function App(s) (default: 3.11)
      --use-localstack        Use azlocal for LocalStack emulator

  # Scenario toggles (all enabled by default)
      --no-basic              Skip basic single-origin scenario
      --no-multi              Skip multi-origins scenario
      --no-spec               Skip route specificity scenario
      --no-rules              Skip rules engine demo
      --no-state              Skip endpoint enabled/disabled state scenario

  -h, --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--name-prefix) NAME_PREFIX=${2:-}; shift 2;;
    -l|--location) LOCATION=${2:-}; shift 2;;
    -g|--resource-group) RESOURCE_GROUP=${2:-}; shift 2;;
    --python-version) PYTHON_VERSION=${2:-}; shift 2;;
    --use-localstack) USE_LOCALSTACK="true"; shift;;
    --no-basic) DO_BASIC="false"; shift;;
    --no-multi) DO_MULTI="false"; shift;;
    --no-spec) DO_SPEC="false"; shift;;
    --no-rules) DO_RULES="false"; shift;;
    --no-state) DO_STATE="false"; shift;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown option: $1" >&2; print_usage; exit 1;;
  esac
done

# -------------------------------
# Paths and assets
# -------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FUNCTION_SRC="$ROOT_DIR/function"
ZIP_MAIN="$ROOT_DIR/app_main.zip"
ZIP_A="$ROOT_DIR/app_A.zip"
ZIP_B="$ROOT_DIR/app_B.zip"
ENV_OUT="$SCRIPT_DIR/.last_deploy_all.env"

# -------------------------------
# Name generation
# -------------------------------
prefix=$(echo "$NAME_PREFIX" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
[[ -z "$prefix" ]] && prefix="demo"
suffix=$(printf "%05d" $(( (RANDOM % 100000) )))

[[ -z "$RESOURCE_GROUP" ]] && RESOURCE_GROUP="rg-$prefix-$suffix"

# Storage + Function Apps
storageMain="st${prefix}${suffix}"; storageMain="${storageMain:0:24}"
funcMain="fa-$prefix-$suffix"

storageA="st${prefix}a${suffix}"; storageA="${storageA:0:24}"
storageB="st${prefix}b${suffix}"; storageB="${storageB:0:24}"
funcA="fa-${prefix}a-$suffix"
funcB="fa-${prefix}b-$suffix"

# AFD profile and endpoints (one profile, multiple endpoints)
profileName="afd-$prefix-$suffix"
epBasic="ep-${prefix}-basic-$suffix"
epMulti="ep-${prefix}-multi-$suffix"
epSpec="ep-${prefix}-spec-$suffix"
epRules="ep-${prefix}-rules-$suffix"
epState="ep-${prefix}-state-$suffix"

# Origin groups and origins
ogBasic="og-${prefix}-basic"
ogSpec="og-${prefix}-spec"
ogRules="og-${prefix}-rules"
ogMulti="og-${prefix}-multi"

orMainBasic="or-${prefix}-main-basic"
orMainSpec="or-${prefix}-main-spec"
orMainRules="or-${prefix}-main-rules"
orA="or-${prefix}-a"
orB="or-${prefix}-b"

# Routes (one per endpoint unless scenario needs multiple)
rtBasic="rt-${prefix}-basic"
rtMultiCatchAll="rt-${prefix}-multi-all"
rtSpecAll="rt-${prefix}-spec-all"
rtSpecJohn="rt-${prefix}-spec-john"
rtRules="rt-${prefix}-rules"
rtState="rt-${prefix}-state"

# Rule Set and Rule names for AFD Rules Engine
# Constraints: must start with a letter and contain only letters and digits (no hyphens/underscores).
# We derive alphanumeric names from the sanitized prefix+suffix used elsewhere.
ruleSetName="rs${prefix}${suffix}"
ruleName="ruleAddHeader"

# -------------------------------
# LocalStack interception lifecycle (optional)
# -------------------------------
INTERCEPTION_STARTED="false"
AZURE_CONFIG_DIR_CREATED="false"
finish() {
  set +e
  [[ -f "$ZIP_MAIN" ]] && rm -f "$ZIP_MAIN"
  [[ -f "$ZIP_A" ]] && rm -f "$ZIP_A"
  [[ -f "$ZIP_B" ]] && rm -f "$ZIP_B"
  if [[ "$INTERCEPTION_STARTED" == "true" ]] && command -v azlocal >/dev/null 2>&1; then
    azlocal stop-interception >/dev/null 2>&1 || true
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
  if azlocal start-interception; then
    INTERCEPTION_STARTED="true"; echo "LocalStack interception started."
  else
    echo "Error: azlocal failed to start interception. Ensure LocalStack is running." >&2
    exit 1
  fi
fi

echo "Resource Group: $RESOURCE_GROUP"

# -------------------------------
# Resource Group
# -------------------------------
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none

# -------------------------------
# Function App(s): create + configure
# -------------------------------
create_function_app() {
  local funcName="$1"; local storageName="$2"
  az storage account create -g "$RESOURCE_GROUP" -n "$storageName" -l "$LOCATION" --sku Standard_LRS --kind StorageV2 -o none
  az functionapp create -g "$RESOURCE_GROUP" -n "$funcName" \
    --consumption-plan-location "$LOCATION" \
    --runtime python --runtime-version "$PYTHON_VERSION" \
    --functions-version 4 --os-type Linux \
    --storage-account "$storageName" --disable-app-insights -o none
  if [[ "$USE_LOCALSTACK" != "true" ]]; then
    az functionapp config appsettings set -g "$RESOURCE_GROUP" -n "$funcName" \
      --settings WEBSITE_RUN_FROM_PACKAGE=1 FUNCTIONS_WORKER_RUNTIME=python SCM_DO_BUILD_DURING_DEPLOYMENT=false -o none
  else
    az functionapp config appsettings set -g "$RESOURCE_GROUP" -n "$funcName" \
      --settings FUNCTIONS_WORKER_RUNTIME=python WEBSITE_RUN_FROM_PACKAGE=0 -o none
    local STORAGE_KEY
    STORAGE_KEY=$(az storage account keys list -g "$RESOURCE_GROUP" -n "$storageName" --query "[0].value" -o tsv)
    if [[ -z "$STORAGE_KEY" ]]; then echo "Failed to get storage key for $storageName" >&2; exit 1; fi
    local STORAGE_CONNECTION_STRING
    STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=http;AccountName=$storageName;AccountKey=$STORAGE_KEY;BlobEndpoint=http://$storageName.blob.localhost.localstack.cloud:4566;QueueEndpoint=http://$storageName.queue.localhost.localstack.cloud:4566;TableEndpoint=http://$storageName.table.localhost.localstack.cloud:4566;FileEndpoint=http://$storageName.file.localhost.localstack.cloud:4566"
    az functionapp config appsettings set -g "$RESOURCE_GROUP" -n "$funcName" \
      --settings AzureWebJobsStorage="$STORAGE_CONNECTION_STRING" WEBSITE_CONTENTAZUREFILECONNECTIONSTRING="$STORAGE_CONNECTION_STRING" SCM_RUN_FROM_PACKAGE= -o none
  fi
}

publish_function_code() {
  local funcName="$1"; local zipPath="$2"
  if [[ "$USE_LOCALSTACK" == "true" ]]; then
    if ! command -v func >/dev/null 2>&1; then
      echo "Error: Azure Functions Core Tools ('func') not found in PATH." >&2; exit 1
    fi
    pushd "$FUNCTION_SRC" >/dev/null
    func azure functionapp publish "$funcName" --python --build local #--verbose --debug
    popd >/dev/null
  else
    rm -f "$zipPath"; ( cd "$FUNCTION_SRC" && zip -rq "$zipPath" . )
    az functionapp deployment source config-zip -g "$RESOURCE_GROUP" -n "$funcName" --src "$zipPath"
  fi
}

if [[ "$DO_BASIC" == "true" || "$DO_SPEC" == "true" || "$DO_RULES" == "true" || "$DO_STATE" == "true" ]]; then
  create_function_app "$funcMain" "$storageMain"
  publish_function_code "$funcMain" "$ZIP_MAIN"
fi

if [[ "$DO_MULTI" == "true" ]]; then
  create_function_app "$funcA" "$storageA"
  create_function_app "$funcB" "$storageB"
  publish_function_code "$funcA" "$ZIP_A"
  publish_function_code "$funcB" "$ZIP_B"
fi

# Resolve hostnames
funcMainHost=""; funcAHost=""; funcBHost=""
if [[ "$DO_BASIC" == "true" || "$DO_SPEC" == "true" || "$DO_RULES" == "true" || "$DO_STATE" == "true" ]]; then
  funcMainHost=$(az functionapp show -g "$RESOURCE_GROUP" -n "$funcMain" --query defaultHostName -o tsv)
fi
if [[ "$DO_MULTI" == "true" ]]; then
  funcAHost=$(az functionapp show -g "$RESOURCE_GROUP" -n "$funcA" --query defaultHostName -o tsv)
  funcBHost=$(az functionapp show -g "$RESOURCE_GROUP" -n "$funcB" --query defaultHostName -o tsv)
fi

# -------------------------------
# Azure Front Door: profile
# -------------------------------
az afd profile create -g "$RESOURCE_GROUP" --profile-name "$profileName" --sku Standard_AzureFrontDoor -o none

# Helper to create endpoint, origin group, origin, and route
create_endpoint_single_origin() {
  local endpointName="$1"; local originGroupName="$2"; local originName="$3"; local routeName="$4"; local funcHost="$5"; local patterns="$6"
  az afd endpoint create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --enabled-state Enabled -o none
  az afd origin-group create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$originGroupName" \
    --probe-request-type GET --probe-protocol Http --probe-interval-in-seconds 120 --probe-path / --sample-size 4 --successful-samples-required 3 --additional-latency-in-milliseconds 0 -o none
  az afd origin create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$originGroupName" --origin-name "$originName" \
    --host-name "$funcHost" --origin-host-header "$funcHost" --http-port 80 --https-port 443 -o none
  az afd route create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --route-name "$routeName" \
    --origin-group "$originGroupName" --patterns-to-match "$patterns" --https-redirect Enabled --supported-protocols Http Https --link-to-default-domain Enabled --forwarding-protocol MatchRequest -o none
}

create_endpoint_multi_origin() {
  local endpointName="$1"; local originGroupName="$2"; local originAName="$3"; local originBName="$4"; local routeName="$5";
  local hostA="$6"; local hostB="$7"; local prioA="$8"; local prioB="$9"; local weightA="${10}"; local weightB="${11}"
  az afd endpoint create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --enabled-state Enabled -o none
  az afd origin-group create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$originGroupName" \
    --probe-request-type HEAD --probe-protocol Http --probe-interval-in-seconds 120 --probe-path / --sample-size 4 --successful-samples-required 3 --additional-latency-in-milliseconds 0 -o none
  az afd origin create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$originGroupName" --origin-name "$originAName" \
    --host-name "$hostA" --origin-host-header "$hostA" --http-port 80 --https-port 443 --priority "$prioA" --weight "$weightA" -o none
  az afd origin create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$originGroupName" --origin-name "$originBName" \
    --host-name "$hostB" --origin-host-header "$hostB" --http-port 80 --https-port 443 --priority "$prioB" --weight "$weightB" -o none
  az afd route create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --route-name "$routeName" \
    --origin-group "$originGroupName" --patterns-to-match '/*' --https-redirect Enabled --supported-protocols Http Https --link-to-default-domain Enabled --forwarding-protocol MatchRequest -o none
}

# Basic single-origin
if [[ "$DO_BASIC" == "true" ]]; then
  create_endpoint_single_origin "$epBasic" "$ogBasic" "$orMainBasic" "$rtBasic" "$funcMainHost" '/*'
fi

# Multi origins
if [[ "$DO_MULTI" == "true" ]]; then
  create_endpoint_multi_origin "$epMulti" "$ogMulti" "$orA" "$orB" "$rtMultiCatchAll" "$funcAHost" "$funcBHost" 1 2 75 25
fi

# Route specificity: create two routes on the same endpoint
if [[ "$DO_SPEC" == "true" ]]; then
  az afd endpoint create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$epSpec" --enabled-state Enabled -o none
  az afd origin-group create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$ogSpec" \
    --probe-request-type GET --probe-protocol Http --probe-interval-in-seconds 120 --probe-path / --sample-size 4 --successful-samples-required 3 --additional-latency-in-milliseconds 0 -o none
  az afd origin create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$ogSpec" --origin-name "$orMainSpec" \
    --host-name "$funcMainHost" --origin-host-header "$funcMainHost" --http-port 80 --https-port 443 -o none
  # Catch-all
  az afd route create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$epSpec" --route-name "$rtSpecAll" \
    --origin-group "$ogSpec" --patterns-to-match '/*' --https-redirect Enabled --supported-protocols Http Https --link-to-default-domain Enabled --forwarding-protocol MatchRequest -o none
  # Specific '/john'
  az afd route create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$epSpec" --route-name "$rtSpecJohn" \
    --origin-group "$ogSpec" --patterns-to-match '/john' --https-redirect Enabled --supported-protocols Http Https --link-to-default-domain Enabled --forwarding-protocol MatchRequest -o none
fi

# Rules engine demo: create rule set with a rule that adds a response header; attach to route
if [[ "$DO_RULES" == "true" ]]; then
  az afd endpoint create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$epRules" --enabled-state Enabled -o none
  az afd origin-group create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$ogRules" \
    --probe-request-type GET --probe-protocol Http --probe-interval-in-seconds 120 --probe-path / --sample-size 4 --successful-samples-required 3 --additional-latency-in-milliseconds 0 -o none
  az afd origin create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$ogRules" --origin-name "$orMainRules" \
    --host-name "$funcMainHost" --origin-host-header "$funcMainHost" --http-port 80 --https-port 443 -o none

  # Create a Rule Set and a Rule. If the Azure CLI extension/command group is unavailable, skip gracefully.
  set +e
  az afd rule-set create -g "$RESOURCE_GROUP" --profile-name "$profileName" --rule-set-name "$ruleSetName" -o none
  RS_STATUS=$?
  set -e
  if [[ $RS_STATUS -eq 0 ]]; then
    # Add Rule 1: ModifyResponseHeader when RequestMethod == GET
    set +e
    az afd rule create \
      -g "$RESOURCE_GROUP" \
      --profile-name "$profileName" \
      --rule-set-name "$ruleSetName" \
      --rule-name "$ruleName" \
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
    RULE_STATUS=$?
    set -e
    # Add Rule 2: UrlRewrite when UrlPath begins with /api -> /
    set +e
    az afd rule create \
      -g "$RESOURCE_GROUP" \
      --profile-name "$profileName" \
      --rule-set-name "$ruleSetName" \
      --rule-name rule2 \
      --order 2 \
      --match-variable UrlPath \
      --operator BeginsWith \
      --match-values /api \
      --negate-condition false \
      --match-processing-behavior Continue \
      --action-name UrlRewrite \
      --destination / -o none
    set -e
    # Add Rule 3: UrlRedirect when UrlPath begins with /old -> /new (302 Found)
    set +e
    az afd rule create \
      -g "$RESOURCE_GROUP" \
      --profile-name "$profileName" \
      --rule-set-name "$ruleSetName" \
      --rule-name rule3 \
      --order 3 \
      --match-variable UrlPath \
      --operator BeginsWith \
      --match-values /old \
      --negate-condition false \
      --action-name UrlRedirect \
      --redirect-type Found \
      --destination /new -o none
    set -e
  else
    echo "Note: 'az afd rule-set' command group not available; skipping rule creation."
    RULE_STATUS=1
  fi

  # Create a route and attach the rule set if created
  if [[ $RS_STATUS -eq 0 ]]; then
    az afd route create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$epRules" --route-name "rt-${prefix}-rules" \
      --origin-group "$ogRules" --patterns-to-match '/*' --https-redirect Enabled --supported-protocols Http Https \
      --link-to-default-domain Enabled --forwarding-protocol MatchRequest --rule-sets "$ruleSetName" -o none
  else
    az afd route create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$epRules" --route-name "rt-${prefix}-rules" \
      --origin-group "$ogRules" --patterns-to-match '/*' --https-redirect Enabled --supported-protocols Http Https \
      --link-to-default-domain Enabled --forwarding-protocol MatchRequest -o none
  fi
fi

# Endpoint enabled/disabled scenario: provision an endpoint we can toggle
if [[ "$DO_STATE" == "true" ]]; then
  create_endpoint_single_origin "$epState" "og-${prefix}-state" "or-${prefix}-state" "rt-${prefix}-state" "$funcMainHost" '/*'
fi

# -------------------------------
# Resolve hostnames for output
# -------------------------------
resolve_ep_host() { az afd endpoint show -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$1" --query hostName -o tsv || true; }

hostBasic=""; hostMulti=""; hostSpec=""; hostRules=""; hostState=""
[[ "$DO_BASIC" == "true" ]] && hostBasic=$(resolve_ep_host "$epBasic")
[[ "$DO_MULTI" == "true" ]] && hostMulti=$(resolve_ep_host "$epMulti")
[[ "$DO_SPEC" == "true" ]] && hostSpec=$(resolve_ep_host "$epSpec")
[[ "$DO_RULES" == "true" ]] && hostRules=$(resolve_ep_host "$epRules")
[[ "$DO_STATE" == "true" ]] && hostState=$(resolve_ep_host "$epState")

# Local addresses for emulator
if [[ "$USE_LOCALSTACK" == "true" ]]; then
  funcMainLocal="${funcMain}website.localhost.localstack.cloud:4566"
  funcALocal="${funcA}website.localhost.localstack.cloud:4566"
  funcBLocal="${funcB}website.localhost.localstack.cloud:4566"
  epBasicLocal="${epBasic}.afd.localhost.localstack.cloud:4566"
  epMultiLocal="${epMulti}.afd.localhost.localstack.cloud:4566"
  epSpecLocal="${epSpec}.afd.localhost.localstack.cloud:4566"
  epRulesLocal="${epRules}.afd.localhost.localstack.cloud:4566"
  epStateLocal="${epState}.afd.localhost.localstack.cloud:4566"
fi

# -------------------------------
# Persist environment for cleanup
# -------------------------------
cat > "$ENV_OUT" <<ENV
RESOURCE_GROUP="$RESOURCE_GROUP"
PROFILE_NAME="$profileName"
EP_BASIC="$epBasic"
EP_MULTI="$epMulti"
EP_SPEC="$epSpec"
EP_RULES="$epRules"
EP_STATE="$epState"
FUNC_MAIN="$funcMain"
FUNC_A="$funcA"
FUNC_B="$funcB"
ENV
echo "Saved deployment environment to: $ENV_OUT"

# -------------------------------
# Output summary and test URLs
# -------------------------------
echo
echo "Deployment complete."
echo "Resource Group: $RESOURCE_GROUP"
if [[ "$DO_BASIC" == "true" ]]; then
  if [[ "$USE_LOCALSTACK" == "true" ]]; then
    echo "[Basic] AFD Local Endpoint:   https://$epBasicLocal/john"
  else
    echo "[Basic] AFD Endpoint:         https://$hostBasic/john"
  fi
fi
if [[ "$DO_MULTI" == "true" ]]; then
  if [[ "$USE_LOCALSTACK" == "true" ]]; then
    echo "[Multi] AFD Local Endpoint:   https://$epMultiLocal/john"
    echo "       You can inspect responses to see which origin served them (function echoes WEBSITE_HOSTNAME)."
  else
    echo "[Multi] AFD Endpoint:         https://$hostMulti/john"
  fi
fi
if [[ "$DO_SPEC" == "true" ]]; then
  if [[ "$USE_LOCALSTACK" == "true" ]]; then
    echo "[Spec]  AFD Local Endpoint:   https://$epSpecLocal/john  (specific route)"
    echo "       Also try:              https://$epSpecLocal/jane  (catch-all)"
  else
    echo "[Spec]  AFD Endpoint:         https://$hostSpec/john  (specific route)"
    echo "       Also try:              https://$hostSpec/jane  (catch-all)"
  fi
fi
if [[ "$DO_RULES" == "true" ]]; then
  if [[ "$USE_LOCALSTACK" == "true" ]]; then
    echo "[Rules] AFD Local Endpoint:   https://$epRulesLocal/john"
    echo "       Expect response header: X-CDN: MSFT (if rules are supported)."
  else
    echo "[Rules] AFD Endpoint:         https://$hostRules/john"
    echo "       Expect response header: X-CDN: MSFT (once propagation completes)."
  fi
fi
if [[ "$DO_STATE" == "true" ]]; then
  if [[ "$USE_LOCALSTACK" == "true" ]]; then
    echo "[State] AFD Local Endpoint:   https://$epStateLocal/john"
  else
    echo "[State] AFD Endpoint:         https://$hostState/john"
  fi
  echo "       To test enabled-state toggle:"
  echo "         az afd endpoint update -g $RESOURCE_GROUP --profile-name $profileName --endpoint-name $epState --enabled-state Disabled"
  echo "         # Then re-enable:"
  echo "         az afd endpoint update -g $RESOURCE_GROUP --profile-name $profileName --endpoint-name $epState --enabled-state Enabled"
fi
