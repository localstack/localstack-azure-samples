#!/usr/bin/env bash
set -euo pipefail

# Helper script to run all sample tests locally, replicating the CI environment.
# Requirements:
# - Docker
# - Python 3.12+
# - .NET 9.0+
# - Node.js & npm
# - Azure CLI (az)
# - LocalStack CLI
# - Terraform CLI
# - azlocal & terraform-local (pip install azlocal terraform-local)
# - Azure Functions Core Tools (func)
# - Azure Functions Core Tools (func)
# - jq & zip (sudo apt-get install jq zip)
# - MSSQL Tools (sqlcmd)
# - LOCALSTACK_AUTH_TOKEN environment variable

# 0. Load environment variables from .env file if it exists
if [ -f .env ]; then
  echo "Loading environment variables from .env file..." >&2
  # Use a subshell to avoid exporting everything if not needed,
  # but here we actually want them in the environment.
  set -a
  source .env
  set +a
fi

# 1. Define Samples (placed before tool checks so --list works without dependencies)
SAMPLES=(
  "samples/servicebus/java|bash scripts/deploy.sh"
  "samples/function-app-front-door/python|bash scripts/deploy_all.sh --name-prefix testafd|"
  "samples/function-app-managed-identity/python|bash scripts/user-managed-identity.sh|bash scripts/validate.sh && bash scripts/test.sh"
  "samples/function-app-service-bus/dotnet|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/call-http-trigger.sh"
  "samples/function-app-storage-http/dotnet|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/call-http-triggers.sh"
  "samples/web-app-cosmosdb-mongodb-api/python|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/call-web-app.sh"
  "samples/web-app-managed-identity/python|bash scripts/user-assigned.sh|bash scripts/validate.sh && bash scripts/call-web-app.sh"
  "samples/web-app-sql-database/python|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/get-web-app-url.sh"
  "samples/aci-blob-storage/python|bash scripts/deploy.sh|bash scripts/validate.sh"
)

# 1a. Define Terraform Samples
TERRAFORM_SAMPLES=(
  "samples/servicebus/java/terraform|bash deploy.sh"
  "samples/function-app-managed-identity/python/terraform|bash deploy.sh"
  "samples/function-app-service-bus/dotnet/terraform|bash deploy.sh"
  "samples/function-app-storage-http/dotnet/terraform|bash deploy.sh"
  "samples/web-app-cosmosdb-mongodb-api/python/terraform|bash deploy.sh"
  "samples/web-app-managed-identity/python/terraform|bash deploy.sh"
  "samples/web-app-sql-database/python/terraform|bash deploy.sh"
  "samples/aci-blob-storage/python/terraform|bash deploy.sh"
)

# 1b. Define Bicep Samples
BICEP_SAMPLES=(
  "samples/servicebus/java/bicep|bash deploy.sh"
  #"samples/web-app-sql-database/python/bicep|bash deploy.sh"
  "samples/function-app-managed-identity/python/bicep|bash deploy.sh"
  "samples/function-app-service-bus/dotnet/bicep|bash deploy.sh"
  "samples/function-app-storage-http/dotnet/bicep|bash deploy.sh"
  "samples/web-app-cosmosdb-mongodb-api/python/bicep|bash deploy.sh"
  "samples/web-app-managed-identity/python/bicep|bash deploy.sh"
  "samples/aci-blob-storage/python/bicep|bash deploy.sh"
)

# Combine script-based, Terraform, and Bicep samples into one array
ALL_SAMPLES=("${SAMPLES[@]}" "${TERRAFORM_SAMPLES[@]}" "${BICEP_SAMPLES[@]}")
TOTAL=${#ALL_SAMPLES[@]}

# 2. Handle --list flag: output JSON metadata for CI matrix generation (no tools required)
#    Each entry has: shard (1-based index), splits (total count), name, and watch_folders.
#    CI uses watch_folders to detect which tests are affected by changed files.
if [[ "${1:-}" == "--list" ]]; then
  echo "["
  for (( i=0; i<TOTAL; i++ )); do
    IFS='|' read -r path _ _ <<< "${ALL_SAMPLES[$i]}"

    if [[ "$path" == */terraform || "$path" == */bicep ]]; then
      watch=("$path" "$(dirname "$path")/src")
      name="${path#samples/}"
    else
      watch=("$path/scripts" "$path/src")
      name="${path#samples/}/scripts"
    fi

    printf '  {"shard":%d,"splits":%d,"name":"%s","watch_folders":["%s","%s"]}' \
      $((i+1)) "$TOTAL" "$name" "${watch[0]}" "${watch[1]}"
    (( i < TOTAL-1 )) && echo "," || echo ""
  done
  echo "]"
  exit 0
fi

# 3. Check for required tools
command -v localstack >/dev/null 2>&1 || { echo >&2 "localstack CLI is required but not installed. Aborting."; exit 1; }
command -v az >/dev/null 2>&1 || { echo >&2 "az CLI is required but not installed. Aborting."; exit 1; }
command -v azlocal >/dev/null 2>&1 || { echo >&2 "azlocal is required but not installed. Run 'pip install azlocal'. Aborting."; exit 1; }
#command -v tflocal >/dev/null 2>&1 || { echo >&2 "tflocal is required but not installed. Run 'pip install terraform-local'. Aborting."; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo >&2 "terraform CLI is required but not installed. Aborting."; exit 1; }
command -v func >/dev/null 2>&1 || { echo >&2 "Azure Functions Core Tools (func) is required but not installed. Aborting."; exit 1; }

if [ -z "${LOCALSTACK_AUTH_TOKEN:-}" ]; then
  echo "Error: LOCALSTACK_AUTH_TOKEN is not set. It is required for the Azure emulator."
  exit 1
fi

# 4. Start LocalStack
if ! localstack status | grep -q "running"; then
  echo "Starting LocalStack Azure emulator..."
  IMAGE_NAME=localstack/localstack-azure-alpha localstack start -d
  localstack wait -t 60
else
  echo "LocalStack is already running."
fi

# 5. Configure Azure CLI for LocalStack
echo "Configuring Azure CLI for LocalStack..."
if [ -n "${AZURE_CONFIG_DIR:-}" ]; then
  mkdir -p "$AZURE_CONFIG_DIR"
fi

if command -v azlocal >/dev/null 2>&1; then
  echo "[DEBUG] azlocal command found, attempting login..."
  azlocal login || true
  echo "[DEBUG] Starting azlocal interception..."
  azlocal start-interception
  echo "[DEBUG] Setting default subscription..."
  azlocal account set --subscription "00000000-0000-0000-0000-000000000000" || true
  echo "[DEBUG] Checking azlocal account status..."
  azlocal account show --query "{Environment:environmentName, Subscription:id}" --output json 2>&1 || echo "[DEBUG] azlocal account show failed"
else
  echo "[DEBUG] azlocal not found, using standard az login with service principal..."
  az login --service-principal -u any-app -p any-pass --tenant any-tenant || true
  echo "[DEBUG] Checking az account status..."
  az account show --query "{Environment:environmentName, Subscription:id}" --output json 2>&1 || echo "[DEBUG] az account show failed"
fi

# 6. Calculate Shard — determines which slice of ALL_SAMPLES to run.
#    When SPLITS=TOTAL, each shard runs exactly 1 test (COUNT=1).
SHARD=${1:-1}
SPLITS=${2:-1}

COUNT=$(( TOTAL / SPLITS ))
START=$(( (SHARD - 1) * COUNT ))

# Last shard picks up any remainder from integer division
if [ "$SHARD" -eq "$SPLITS" ]; then
  COUNT=$(( TOTAL - START ))
fi

echo "Running samples shard $SHARD of $SPLITS (index $START, count $COUNT)"
echo "Total samples (scripts + terraform + bicep): $TOTAL"

# 7. Run Samples — deploy each test, then run its validation if defined
for (( i=START; i<START+COUNT; i++ )); do
  item="${ALL_SAMPLES[$i]}"
  IFS='|' read -r path deploy test <<< "$item"
  echo "============================================================"
  echo "Testing Sample: $path"
  echo "============================================================"

  pushd "$path" > /dev/null

  echo "Deploying..."
  eval "$deploy"

  if [ -n "$test" ]; then
    echo "Testing..."
    eval "$test"
  fi

  # Cleanup Terraform state for terraform tests
  if [[ "$path" == *"/terraform" ]]; then
    echo "Cleaning up Terraform state..."
    rm -rf .terraform terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl tfplan || true
  fi

  # Cleanup Bicep artifacts for bicep tests
  if [[ "$path" == *"/bicep" ]]; then
    echo "Cleaning up Bicep artifacts..."
    rm -f *.zip || true
  fi

  popd > /dev/null
  echo "Completed: $path"

  # Clean up Azure resources to prevent state pollution between tests
  echo "Cleaning up Azure resources in LocalStack..."
  if command -v azlocal >/dev/null 2>&1; then
    RG_LIST=$(azlocal group list --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$RG_LIST" ]]; then
      echo "$RG_LIST" | while read -r rg; do
        if [[ -n "$rg" ]]; then
          echo "  - Deleting resource group: $rg"
          azlocal group delete --name "$rg" --yes --no-wait 2>/dev/null || true
        fi
      done
      sleep 2
    else
      echo "  No resource groups to clean up"
    fi
  fi

  # Cleanup Docker resources after each test to free up disk space
  echo "Cleaning up Docker resources..."
  docker system prune -af --volumes || true
  echo ""
done

echo "All samples completed successfully!"
