#!/usr/bin/env bash
set -euo pipefail

# What this example is trying to achieve and how:
#  - It creates two almost-identical Function Apps (A and B) and puts both in a single AFD origin group.
#  - You control the origin priorities and weights via flags. The AFD data plane (implemented in dataplane.py)
#    will select the target origin at request time based on health, priority, and weight.
#  - By calling the AFD endpoint repeatedly, you can observe:
#      • Priority behavior: with A=1 and B=2, responses should come only from A while it’s healthy; if A fails
#        the probe, traffic shifts to B until A is healthy again.
#      • Weighted behavior: with A=1/B=1 and weights 75/25, a batch of requests should roughly split 75/25
#        between A and B (probabilistic).
#  - For visibility, you can modify your function to echo the WEBSITE_HOSTNAME or a hard-coded tag (origin=A/B),
#    or watch the LocalStack logs which include selected origin messages.
#
# Relation to dataplane code:
#  - This validates section 11.1 in dpinvestigation.md and the logic added to localstack-pro-azure/.../cdn/dataplane.py
#    which implements priority + weighted selection and group-level health probes.
#
# Requirements: az CLI, bash, zip
# Optional for LocalStack mode (--use-localstack):
#   - azlocal: intercepts az CLI for the LocalStack Azure emulator
#   - funclocal + Azure Functions Core Tools ('func'): to publish functions when not using Kudu zip deploy
#
# Example usages in localstack:
#  1) Priority failover (A primary, B secondary)
#     bash ./scripts/deploy_multi_origins.sh --name-prefix mydemo --use-localstack --prio-a 1 --prio-b 2 --weight-a 50 --weight-b 50
#
#  2) Weighted distribution (both priority=1, 3:1 split)
#     bash ./scripts/deploy_multi_origins.sh --name-prefix mydemo --use-localstack --prio-a 1 --prio-b 1 --weight-a 75 --weight-b 25
#

# -------------------------------
# Defaults (overridable via flags)
# -------------------------------
# These influence the names/locations of resources and the runtime behavior of the test.
# - NAME_PREFIX helps make unique, readable names.
# - USE_LOCALSTACK switches between native Azure and LocalStack emulator.
# - PRIO_*/WEIGHT_* control origin selection at the data plane (what we want to test).
# - PROBE_* configure the Origin Group health probe that gates origin eligibility.
NAME_PREFIX="funcafd2"
LOCATION="eastus"
RESOURCE_GROUP=""
USE_LOCALSTACK="false"
PYTHON_VERSION="3.11"

# Origin selection defaults
PRIO_A=1
PRIO_B=2
WEIGHT_A=75
WEIGHT_B=25

# Probe defaults (group-level)
PROBE_PATH="/"
PROBE_METHOD="HEAD"     # GET or HEAD
PROBE_PROTOCOL="Http"   # Http or Https
PROBE_INTERVAL=120       # seconds

print_usage() {
  cat <<EOF
Usage: 
  $(basename "$0") [options]

Options:
  -p, --name-prefix STR       Base name prefix (default: funcafd2)
  -l, --location STR          Azure region (default: eastus)
  -g, --resource-group STR    Resource group name (auto-generated if omitted)
      --python-version STR    Python runtime version for Function Apps (default: 3.11)
      --use-localstack        Use azlocal/funclocal for LocalStack emulator
      --prio-a INT            Priority for Origin A (default: 1; lower = higher priority)
      --prio-b INT            Priority for Origin B (default: 2)
      --weight-a INT          Weight for Origin A (default: 75)
      --weight-b INT          Weight for Origin B (default: 25)
      --probe-path STR        Probe path (default: /)
      --probe-method STR      Probe method GET|HEAD (default: HEAD)
      --probe-protocol STR    Probe protocol Http|Https (default: Http)
      --probe-interval INT    Probe interval seconds (default: 120)
  -h, --help                  Show this help
EOF
}

# -------------------------------
# Parse arguments
# -------------------------------
# We accept flags to control both infrastructure (names, location) and test behavior
# (priorities, weights, and probe config). This lets you re-run the same script for
# different scenarios (failover vs weighted) without editing the file.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--name-prefix) NAME_PREFIX=${2:-}; shift 2;;
    -l|--location) LOCATION=${2:-}; shift 2;;
    -g|--resource-group) RESOURCE_GROUP=${2:-}; shift 2;;
    --python-version) PYTHON_VERSION=${2:-}; shift 2;;
    --use-localstack) USE_LOCALSTACK="true"; shift;;
    --prio-a) PRIO_A=${2:-}; shift 2;;
    --prio-b) PRIO_B=${2:-}; shift 2;;
    --weight-a) WEIGHT_A=${2:-}; shift 2;;
    --weight-b) WEIGHT_B=${2:-}; shift 2;;
    --probe-path) PROBE_PATH=${2:-}; shift 2;;
    --probe-method) PROBE_METHOD=${2:-}; shift 2;;
    --probe-protocol) PROBE_PROTOCOL=${2:-}; shift 2;;
    --probe-interval) PROBE_INTERVAL=${2:-}; shift 2;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown option: $1" >&2; print_usage; exit 1;;
  esac
done

# -------------------------------
# Paths
# -------------------------------
# Locate the script root and the function source to package/publish. We create
# two temporary zip files only for the native Azure path (Kudu zip deploy).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FUNCTION_SRC="$ROOT_DIR/function"
ZIP_A="$ROOT_DIR/appA.zip"
ZIP_B="$ROOT_DIR/appB.zip"

# -------------------------------
# Name generation
# -------------------------------
# We derive unique, compliant names for Azure resources. This matters because names
# are globally scoped for some resources (e.g., storage), and also helps you run the
# test multiple times in parallel without collisions.
# - storageA/storageB: separate storage accounts per Function App (simplifies cleanup)
# - funcA/funcB: two function apps that will act as distinct AFD origins
# - originAName/originBName: origin resource names where we will apply priorities/weights
prefix=$(echo "$NAME_PREFIX" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
if [[ -z "$prefix" ]]; then prefix="demo"; fi
suffix=$(printf "%05d" $(((RANDOM % 100000))))

if [[ -z "$RESOURCE_GROUP" ]]; then RESOURCE_GROUP="rg-$prefix-$suffix"; fi

# Storage accounts must be <=24 chars, lowercase alphanum only
storageA="st${prefix}a${suffix}"; storageA="${storageA:0:24}"
storageB="st${prefix}b${suffix}"; storageB="${storageB:0:24}"

funcA="fa-${prefix}a-${suffix}"
funcB="fa-${prefix}b-${suffix}"

profileName="afd-$prefix-$suffix"
endpointName="ep-$prefix-$suffix"
originGroupName="og-$prefix"
originAName="or-${prefix}-a"
originBName="or-${prefix}-b"
routeName="rt-$prefix"

# -------------------------------
# LocalStack interception lifecycle
# -------------------------------
# In emulator mode (--use-localstack), we:
#   - Create an isolated AZURE_CONFIG_DIR to avoid clobbering your global Azure CLI config
#   - Start azlocal interception so 'az' commands are routed to LocalStack
#   - Ensure we stop interception and clean temp files on exit (trap finish)
# In native Azure (default), this section is skipped.
INTERCEPTION_STARTED="false"
AZURE_CONFIG_DIR_CREATED="false"
finish() {
  set +e
  if [[ -f "$ZIP_A" ]]; then rm -f "$ZIP_A"; fi
  if [[ -f "$ZIP_B" ]]; then rm -f "$ZIP_B"; fi
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
# Before creating anything, we print the resolved resource names and the AFD
# origin selection parameters you chose. This makes it easy to copy/paste the
# values into your notes and into the cleanup script later.
# - AFD Origin A/B lines include the chosen priority and weight, which is what
#   we intend to test at the data plane.
echo "Using names:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Storage A:      $storageA"
echo "  Storage B:      $storageB"
echo "  Function A:     $funcA"
echo "  Function B:     $funcB"
echo "  AFD Profile:    $profileName"
echo "  AFD Endpoint:   $endpointName"
echo "  AFD OriginGrp:  $originGroupName"
echo "  AFD Origin A:   $originAName (prio=$PRIO_A, weight=$WEIGHT_A)"
echo "  AFD Origin B:   $originBName (prio=$PRIO_B, weight=$WEIGHT_B)"
echo "  AFD Route:      $routeName"

echo "Probe settings: path=$PROBE_PATH method=$PROBE_METHOD protocol=$PROBE_PROTOCOL interval=$PROBE_INTERVAL"

# -------------------------------
# Create RG and Storage accounts
# -------------------------------
# One resource group contains everything, making cleanup simple. We provision two
# separate storage accounts (A/B) so each Function App has its own storage, which
# mirrors common real-world setups and avoids cross-app state.
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none
az storage account create -g "$RESOURCE_GROUP" -n "$storageA" -l "$LOCATION" --sku Standard_LRS --kind StorageV2 -o none
az storage account create -g "$RESOURCE_GROUP" -n "$storageB" -l "$LOCATION" --sku Standard_LRS --kind StorageV2 -o none

# -------------------------------
# Create Function Apps
# -------------------------------
# We deploy two Linux Consumption (Functions v4) apps running Python. Each app gets its own
# storage account. These two apps will become Origin A and Origin B in the AFD Origin Group.
create_func() {
  local rg=$1 name=$2 storage=$3
  az functionapp create \
    -g "$rg" \
    -n "$name" \
    --consumption-plan-location "$LOCATION" \
    --runtime python \
    --runtime-version "$PYTHON_VERSION" \
    --functions-version 4 \
    --os-type Linux \
    --storage-account "$storage" \
    --disable-app-insights -o none
}

create_func "$RESOURCE_GROUP" "$funcA" "$storageA"
create_func "$RESOURCE_GROUP" "$funcB" "$storageB"

# App settings
# Configure required app settings. In native Azure we use WEBSITE_RUN_FROM_PACKAGE=1 to run
# directly from the zip package. In LocalStack emulator mode, we disable run-from-package and
# provide explicit AzureWebJobsStorage connection strings because automatic wiring differs.
if [[ "$USE_LOCALSTACK" != "true" ]]; then
  az functionapp config appsettings set -g "$RESOURCE_GROUP" -n "$funcA" --settings WEBSITE_RUN_FROM_PACKAGE=1 FUNCTIONS_WORKER_RUNTIME=python SCM_DO_BUILD_DURING_DEPLOYMENT=false -o none
  az functionapp config appsettings set -g "$RESOURCE_GROUP" -n "$funcB" --settings WEBSITE_RUN_FROM_PACKAGE=1 FUNCTIONS_WORKER_RUNTIME=python SCM_DO_BUILD_DURING_DEPLOYMENT=false -o none
else
  az functionapp config appsettings set -g "$RESOURCE_GROUP" -n "$funcA" --settings FUNCTIONS_WORKER_RUNTIME=python WEBSITE_RUN_FROM_PACKAGE=0 -o none
  az functionapp config appsettings set -g "$RESOURCE_GROUP" -n "$funcB" --settings FUNCTIONS_WORKER_RUNTIME=python WEBSITE_RUN_FROM_PACKAGE=0 -o none

  # Construct and set explicit Storage connection strings in emulator mode
  KEY_A=$(az storage account keys list -g "$RESOURCE_GROUP" -n "$storageA" --query "[0].value" -o tsv)
  KEY_B=$(az storage account keys list -g "$RESOURCE_GROUP" -n "$storageB" --query "[0].value" -o tsv)
  if [[ -z "$KEY_A" || -z "$KEY_B" ]]; then
    echo "Failed to retrieve storage account keys" >&2; exit 1
  fi
  CONN_A="DefaultEndpointsProtocol=https;AccountName=$storageA;AccountKey=$KEY_A;BlobEndpoint=https://$storageA.blob.localhost.localstack.cloud:4566;QueueEndpoint=https://$storageA.queue.localhost.localstack.cloud:4566;TableEndpoint=https://$storageA.table.localhost.localstack.cloud:4566;FileEndpoint=https://$storageA.file.localhost.localstack.cloud:4566"
  CONN_B="DefaultEndpointsProtocol=https;AccountName=$storageB;AccountKey=$KEY_B;BlobEndpoint=https://$storageB.blob.localhost.localstack.cloud:4566;QueueEndpoint=https://$storageB.queue.localhost.localstack.cloud:4566;TableEndpoint=https://$storageB.table.localhost.localstack.cloud:4566;FileEndpoint=https://$storageB.file.localhost.localstack.cloud:4566"
  az functionapp config appsettings set -g "$RESOURCE_GROUP" -n "$funcA" --settings AzureWebJobsStorage="$CONN_A" WEBSITE_CONTENTAZUREFILECONNECTIONSTRING="$CONN_A" SCM_RUN_FROM_PACKAGE= -o none
  az functionapp config appsettings set -g "$RESOURCE_GROUP" -n "$funcB" --settings AzureWebJobsStorage="$CONN_B" WEBSITE_CONTENTAZUREFILECONNECTIONSTRING="$CONN_B" SCM_RUN_FROM_PACKAGE= -o none
fi

# -------------------------------
# Deploy code to both apps
# -------------------------------
if [[ ! -d "$FUNCTION_SRC" ]]; then
  echo "Function source folder not found: $FUNCTION_SRC" >&2
  exit 1
fi

if [[ "$USE_LOCALSTACK" == "true" ]]; then
  if ! command -v funclocal >/dev/null 2>&1; then
    echo "Error: funclocal is required when using --use-localstack to publish." >&2
    exit 1
  fi
  if ! command -v func >/dev/null 2>&1; then
    echo "Error: Azure Functions Core Tools ('func') not found in PATH." >&2
    exit 1
  fi
  pushd "$FUNCTION_SRC" >/dev/null
  funclocal azure functionapp publish "$funcA" --python --build local --verbose --debug
  funclocal azure functionapp publish "$funcB" --python --build local --verbose --debug
  popd >/dev/null
else
  rm -f "$ZIP_A" "$ZIP_B"
  ( cd "$FUNCTION_SRC" && zip -rq "$ZIP_A" . )
  cp -f "$ZIP_A" "$ZIP_B"
  az functionapp deployment source config-zip -g "$RESOURCE_GROUP" -n "$funcA" --src "$ZIP_A"
  az functionapp deployment source config-zip -g "$RESOURCE_GROUP" -n "$funcB" --src "$ZIP_B"
fi

# -------------------------------
# Resolve hostnames and craft test URLs
# -------------------------------
# We fetch each Function App's default host name. These are used to configure AFD origins
# and also let you hit the functions directly (control test) versus via AFD (data-plane test).
# In LocalStack mode we also print local developer-friendly hosts on :4566 for convenience.
funcHostA=$(az functionapp show -g "$RESOURCE_GROUP" -n "$funcA" --query defaultHostName -o tsv)
funcHostB=$(az functionapp show -g "$RESOURCE_GROUP" -n "$funcB" --query defaultHostName -o tsv)
if [[ -z "$funcHostA" || -z "$funcHostB" ]]; then
  echo "Could not resolve function defaultHostName(s)" >&2
  exit 1
fi

if [[ "$USE_LOCALSTACK" == "true" ]]; then
  funcLocalA="${funcA}website.localhost.localstack.cloud:4566"
  funcLocalB="${funcB}website.localhost.localstack.cloud:4566"
  testFuncA="https://${funcLocalA}/john"
  testFuncB="https://${funcLocalB}/john"
  afdLocalHost="${endpointName}.afd.localhost.localstack.cloud:4566"
  afdTestUrl="https://${afdLocalHost}/john"
else
  testFuncA="https://${funcHostA}/john"
  testFuncB="https://${funcHostB}/john"
fi

# -------------------------------
# Provision AFD with two origins in one origin group
# -------------------------------
# We create the AFD profile and endpoint (public entry), then an origin group with a
# health probe, and finally two origins (A and B) with your chosen priorities/weights.
# The route maps all paths (/*) to the origin group and preserves the client protocol
# (forwarding-protocol MatchRequest) while enforcing HTTPS redirect at the edge.
az afd profile create -g "$RESOURCE_GROUP" --profile-name "$profileName" --sku Standard_AzureFrontDoor -o none
az afd endpoint create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --enabled-state Enabled -o none

# Create origin group with probes
# The Origin Group is where health is determined. Only healthy origins are eligible.
# - probe-path/method/protocol/interval define how the data plane checks health.
# - In our dataplane implementation, 2xx/3xx results are considered healthy and results are
#   cached per origin for the interval to avoid probing on every request.
az afd origin-group create \
  -g "$RESOURCE_GROUP" \
  --profile-name "$profileName" \
  --origin-group-name "$originGroupName" \
  --probe-request-type "$PROBE_METHOD" \
  --probe-protocol "$PROBE_PROTOCOL" \
  --probe-interval-in-seconds "$PROBE_INTERVAL" \
  --probe-path "$PROBE_PATH" \
  --sample-size 4 \
  --successful-samples-required 3 \
  --additional-latency-in-milliseconds 0 -o none

# Create both origins (pointing to each Function App default host)
# This is the heart of the test. Here we set distinct priorities and weights.
# - Priority: lower number wins; only the lowest priority among healthy origins is used.
# - Weight: among same-priority healthy origins, traffic is distributed proportionally
#   to these weights (if all 0, selection falls back to uniform among candidates).
az afd origin create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$originGroupName" \
  --origin-name "$originAName" --host-name "$funcHostA" --origin-host-header "$funcHostA" \
  --http-port 80 --https-port 443 --priority "$PRIO_A" --weight "$WEIGHT_A" -o none

az afd origin create -g "$RESOURCE_GROUP" --profile-name "$profileName" --origin-group-name "$originGroupName" \
  --origin-name "$originBName" --host-name "$funcHostB" --origin-host-header "$funcHostB" \
  --http-port 80 --https-port 443 --priority "$PRIO_B" --weight "$WEIGHT_B" -o none

# Create a simple catch-all route
# Route behavior:
# - patterns-to-match '/*' means all paths hit this route
# - https-redirect Enabled enforces edge-side HTTP->HTTPS redirects for client traffic
# - forwarding-protocol MatchRequest forwards using the same protocol the client used
# - link-to-default-domain Enabled exposes the Azure-provided endpoint host
az afd route create -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" \
  --route-name "$routeName" --origin-group "$originGroupName" --patterns-to-match '/*' \
  --https-redirect Enabled --supported-protocols Http Https --link-to-default-domain Enabled \
  --forwarding-protocol MatchRequest -o none

# Lookup AFD endpoint hostname (may take time to be fully active)
afdHost=$(az afd endpoint show -g "$RESOURCE_GROUP" --profile-name "$profileName" --endpoint-name "$endpointName" --query hostName -o tsv || true)

# -------------------------------
# Summary and test hints
# -------------------------------
echo
echo "Deployment complete."
echo "Resource Group: $RESOURCE_GROUP"
echo "Function A Host: $funcHostA"
echo "Function B Host: $funcHostB"
if [[ "$USE_LOCALSTACK" == "true" ]]; then
  echo "Test Function A (local): $testFuncA"
  echo "Test Function B (local): $testFuncB"
  echo "AFD Local Endpoint: ${afdLocalHost:-$endpointName.afd.localhost.localstack.cloud}"
  echo "Test via AFD (local): ${afdTestUrl:-https://$endpointName.afd.localhost.localstack.cloud/john}"
else
  echo "Test Function A: $testFuncA"
  echo "Test Function B: $testFuncB"
  if [[ -n "$afdHost" ]]; then
    echo "Test via AFD: https://$afdHost/john"
  fi
fi

echo
echo "Next steps (examples):"
echo "  - Priority failover: set --prio-a 1 --prio-b 2. While both healthy, A should receive all traffic."
echo "  - Weighted distribution: set both priorities to 1 and weights e.g., --weight-a 75 --weight-b 25."
echo "  - Health probes: use --probe-path /health --probe-method HEAD --probe-interval 30 to adjust sensitivity."
echo
cat <<'EOC'
Tips to observe which origin served the request:
- Recommended: modify your function to include an origin tag in the response (e.g., echo WEBSITE_HOSTNAME).
- Alternatively, enable debug logs in LocalStack and watch for lines like:
    [AFD] Selected origin by weight among priority=...: origin=or-...-a ...
- You can also send many requests to observe distribution (PowerShell example):
    1..100 | ForEach-Object { curl -sk https://<afd-host-or-local>/john } | Group-Object | Select-Object Name,Count
EOC
