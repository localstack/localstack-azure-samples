#!/usr/bin/env bash
set -euo pipefail

# Helper script to run all sample tests locally, replicating the CI environment.
# Requirements:
# - Docker
# - Python 3.12+
# - .NET 10.0+
# - Node.js & npm
# - Azure CLI (az)
# - LocalStack CLI
# - Terraform CLI
# - lstk CLI (https://github.com/localstack/lstk)
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

PURGE_DOCKER="${PURGE_DOCKER:-0}"

# 1. Define Samples (placed before tool checks so --list works without dependencies)
SAMPLES=(
  "samples/servicebus/java|bash scripts/deploy.sh"
  "samples/eventhubs/python|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/run-pipeline.sh"
  "samples/function-app-front-door/python|bash scripts/deploy_all.sh --name-prefix testafd|"
  "samples/function-app-managed-identity/python|bash scripts/user-managed-identity.sh|bash scripts/validate.sh && bash scripts/test.sh"
  "samples/function-app-service-bus/dotnet|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/call-http-trigger.sh"
  "samples/function-app-storage-http/dotnet|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/call-http-triggers.sh"
  "samples/web-app-cosmosdb-mongodb-api/python|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/call-web-app.sh"
  "samples/web-app-managed-identity/python|bash scripts/user-assigned.sh|bash scripts/validate.sh && bash scripts/call-web-app.sh"
  "samples/web-app-sql-database/python|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/get-web-app-url.sh"
  "samples/web-app-mysql-flexible-server/python|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/call-web-app.sh"
  "samples/web-app-postgresql-flexible-server/python|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/call-web-app.sh"
  "samples/web-app-custom-image/python|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/call-web-app.sh"
  "samples/aci-blob-storage/python|bash scripts/deploy.sh|bash scripts/validate.sh"
  "samples/multi-service-app/python|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/call-web-app.sh"
)

# 1a. Define Terraform Samples
TERRAFORM_SAMPLES=(
  "samples/servicebus/java/terraform|bash deploy.sh"
  "samples/eventhubs/python/terraform|bash deploy.sh|bash ../scripts/validate.sh"
  "samples/function-app-managed-identity/python/terraform|bash deploy.sh"
  "samples/function-app-service-bus/dotnet/terraform|bash deploy.sh"
  "samples/function-app-storage-http/dotnet/terraform|bash deploy.sh"
  "samples/web-app-cosmosdb-mongodb-api/python/terraform|bash deploy.sh"
  "samples/web-app-managed-identity/python/terraform|bash deploy.sh"
  "samples/web-app-sql-database/python/terraform|bash deploy.sh"
  "samples/web-app-mysql-flexible-server/python/terraform|bash deploy.sh"
  "samples/web-app-postgresql-flexible-server/python/terraform|bash deploy.sh"
  "samples/aci-blob-storage/python/terraform|bash deploy.sh"
  "samples/multi-service-app/python/terraform|bash deploy.sh"
)

# 1b. Define Bicep Samples
BICEP_SAMPLES=(
  "samples/servicebus/java/bicep|bash deploy.sh"
  "samples/eventhubs/python/bicep|bash deploy.sh|bash ../scripts/validate.sh"
  #"samples/web-app-sql-database/python/bicep|bash deploy.sh"
  "samples/function-app-managed-identity/python/bicep|bash deploy.sh"
  "samples/function-app-service-bus/dotnet/bicep|bash deploy.sh"
  "samples/function-app-storage-http/dotnet/bicep|bash deploy.sh"
  "samples/web-app-cosmosdb-mongodb-api/python/bicep|bash deploy.sh"
  "samples/web-app-managed-identity/python/bicep|bash deploy.sh"
  "samples/web-app-mysql-flexible-server/python/bicep|bash deploy.sh"
  "samples/web-app-postgresql-flexible-server/python/bicep|bash deploy.sh"
  "samples/aci-blob-storage/python/bicep|bash deploy.sh"
  "samples/multi-service-app/python/bicep|bash deploy.sh"
)

# Combine script-based, Terraform, and Bicep samples into one array
ALL_SAMPLES=("${SAMPLES[@]}" "${TERRAFORM_SAMPLES[@]}" "${BICEP_SAMPLES[@]}")
TOTAL=${#ALL_SAMPLES[@]}

# 1c. Architecture support
# Samples listed here run *natively* on both amd64 and arm64 (Apple Silicon, arm64 CI
# runners). For everything else, the container image the emulator starts is published by
# Microsoft for amd64 alone — there is no arm64 manifest:
#   - `az webapp create --runtime ...` (code deployment) runs the app on
#     mcr.microsoft.com/oryx/<platform>, which is amd64-only. That rules out every
#     web-app-* sample, plus eventhubs (it deploys a dashboard web app).
#   - Java App Service uses mcr.microsoft.com/azure-app-service/java — amd64-only.
#   - SQL Database is backed by mcr.microsoft.com/mssql/server — amd64-only.
# The samples below avoid all of those: Function Apps get an image built from a
# multi-arch base (arm64 support added in localstack-pro#8102), and the custom-image
# Web App and ACI samples run an image the sample itself builds. Their Cosmos DB,
# Service Bus, Storage and Front Door dependencies all publish arm64 manifests.
#
# "amd64-only" means *not native* — not "cannot run". The emulator never pins
# --platform, so on an arm64 host Docker pulls the amd64 manifest and runs it under
# whatever emulation the runtime provides. Docker Desktop on Apple Silicon emulates it
# via Rosetta, which is why these samples do work on a Mac, just more slowly. They fail
# on an arm64 host with no emulation registered, such as GitHub's ubuntu-*-arm runners,
# so CI schedules only the natively-supported samples below on arm64.
#
# LocalStack's own test suite draws the same line: after localstack-pro#8102, Web App
# tests that only assert SCM/deployment records run on arm64, while the ones that
# exercise a *running* Oryx app (test_deploy_zip_that_accesses_storage,
# test_deploy_zip_without_basic_auth) are still marked @only_on_amd64.
ARM64_SAMPLE_DIRS=(
  "samples/aci-blob-storage/python"
  "samples/function-app-front-door/python"
  "samples/function-app-managed-identity/python"
  "samples/function-app-service-bus/dotnet"
  "samples/function-app-storage-http/dotnet"
  "samples/web-app-custom-image/python"
)

# Fail loudly if an entry no longer matches a registered sample: a rename would otherwise
# silently drop that sample's arm64 coverage while CI stays green.
for _arm64_dir in "${ARM64_SAMPLE_DIRS[@]}"; do
  if ! printf '%s\n' "${ALL_SAMPLES[@]}" | cut -d'|' -f1 | sed -E 's#/(terraform|bicep)$##' | grep -qxF "$_arm64_dir"; then
    echo >&2 "ARM64_SAMPLE_DIRS entry '$_arm64_dir' matches no registered sample - fix the path or remove the entry."
    exit 1
  fi
done

# Architecture support is a property of the sample itself, not of the deployment method,
# so strip the /terraform or /bicep suffix before matching against ARM64_SAMPLE_DIRS.
supports_arm64() {
  local path="$1" family dir
  case "$path" in
    */terraform | */bicep) family=$(dirname "$path") ;;
    *) family="$path" ;;
  esac
  for dir in "${ARM64_SAMPLE_DIRS[@]}"; do
    [[ "$dir" == "$family" ]] && return 0
  done
  return 1
}

# Normalise `uname -m` to the architecture names used above. Anything not recognisably
# arm64 is reported as amd64, so an exotic host (armv7l, ppc64le, ...) takes the amd64
# path and gets no arm64 warning: it errs toward "run it and let the deployment fail"
# rather than skipping silently.
host_arch() {
  case "$(uname -m)" in
    aarch64 | arm64) echo "arm64" ;;
    x86_64 | amd64) echo "amd64" ;;
    *)
      echo >&2 "Note: unrecognised architecture '$(uname -m)'; treating it as amd64."
      echo "amd64"
      ;;
  esac
}

# 2. Handle --list flag: output JSON metadata for CI matrix generation (no tools required)
#    Each entry has: shard (1-based index), splits (total count), name, watch_folders,
#    and arches. CI uses watch_folders to detect which tests are affected by changed
#    files, and arches to decide which architectures to run the test on.
if [[ "${1:-}" == "--list" ]]; then
  echo "["
  for (( i=0; i<TOTAL; i++ )); do
    IFS='|' read -r path _ _ <<< "${ALL_SAMPLES[$i]}"

    if [[ "$path" == */terraform || "$path" == */bicep ]]; then
      # An IaC sample deploys from its own folder, but its test command may run the
      # sample's shared scripts, so a change there has to re-run it too. Folders that do
      # not exist simply never match a changed file.
      watch=("$path" "$(dirname "$path")/src" "$(dirname "$path")/scripts")
      name="${path#samples/}"
    else
      watch=("$path/scripts" "$path/src")
      name="${path#samples/}/scripts"
    fi

    folders=$(printf '"%s",' "${watch[@]}")

    if supports_arm64 "$path"; then
      arches='"amd64","arm64"'
    else
      arches='"amd64"'
    fi

    printf '  {"shard":%d,"splits":%d,"name":"%s","watch_folders":[%s],"arches":[%s]}' \
      $((i+1)) "$TOTAL" "$name" "${folders%,}" "$arches"
    (( i < TOTAL-1 )) && echo "," || echo ""
  done
  echo "]"
  exit 0
fi

# 3. Check for required tools
command -v localstack >/dev/null 2>&1 || { echo >&2 "localstack CLI is required but not installed. Aborting."; exit 1; }
command -v az >/dev/null 2>&1 || { echo >&2 "az CLI is required but not installed. Aborting."; exit 1; }
command -v lstk >/dev/null 2>&1 || { echo >&2 "lstk is required but not installed. See https://github.com/localstack/lstk#installation. Aborting."; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo >&2 "terraform CLI is required but not installed. Aborting."; exit 1; }

if [ -z "${LOCALSTACK_AUTH_TOKEN:-}" ]; then
  echo "Error: LOCALSTACK_AUTH_TOKEN is not set. It is required for the Azure emulator."
  exit 1
fi

# 4. Start LocalStack
if ! localstack status | grep -q "running"; then
  echo "Starting LocalStack Azure emulator..."
  IMAGE_NAME=localstack/localstack-azure localstack start -d
  localstack wait -t 60
else
  echo "LocalStack is already running."
fi

# 5. Configure Azure CLI for LocalStack
echo "Configuring Azure CLI for LocalStack..."
if [ -n "${AZURE_CONFIG_DIR:-}" ]; then
  mkdir -p "$AZURE_CONFIG_DIR"
fi

if command -v lstk >/dev/null 2>&1; then
  echo "[DEBUG] Starting lstk az interception..."
  lstk az start-interception
  # With interception active, the standard az CLI targets the emulator directly.
  # The `lstk az` proxy is intentionally not used below: it requires a one-time
  # Azure CLI integration setup that is not available on headless CI runners.
  echo "[DEBUG] Logging in..."
  az login --service-principal -u any-app -p any-pass --tenant any-tenant || true
  echo "[DEBUG] Setting default subscription..."
  az account set --subscription "00000000-0000-0000-0000-000000000000" || true
  echo "[DEBUG] Checking az account status..."
  az account show --query "{Environment:environmentName, Subscription:id}" --output json 2>&1 || echo "[DEBUG] az account show failed"
else
  echo "[DEBUG] lstk not found, using standard az login with service principal..."
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

HOST_ARCH=$(host_arch)

echo "Running samples shard $SHARD of $SPLITS (index $START, count $COUNT)"
echo "Total samples (scripts + terraform + bicep): $TOTAL"
echo "Host architecture: $HOST_ARCH"

# 7. Run Samples — deploy each test, then run its validation if defined
for (( i=START; i<START+COUNT; i++ )); do
  item="${ALL_SAMPLES[$i]}"
  IFS='|' read -r path deploy test <<< "$item"
  echo "============================================================"
  echo "Testing Sample: $path"
  echo "============================================================"

  # Warn rather than skip: on an arm64 host these still run under amd64 emulation
  # (Rosetta on Docker Desktop), just slowly. Set SKIP_AMD64_ONLY=1 to skip them
  # instead — useful on an arm64 host with no emulation registered, where they would
  # otherwise fail with an opaque error deep inside a deployment.
  if [[ "$HOST_ARCH" == "arm64" ]] && ! supports_arm64 "$path"; then
    if [[ "${SKIP_AMD64_ONLY:-0}" == "1" ]]; then
      echo "Skipped: $path needs an amd64-only container image (SKIP_AMD64_ONLY=1)."
      continue
    fi
    echo "Note: $path needs an amd64-only container image; on arm64 it runs under"
    echo "      emulation (slower) and fails outright if the runtime cannot emulate"
    echo "      amd64. Set SKIP_AMD64_ONLY=1 to skip these instead."
  fi

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
  if command -v lstk >/dev/null 2>&1; then
    # Interception is active (started above), so plain az targets the emulator.
    RG_LIST=$(az group list --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$RG_LIST" ]]; then
      echo "$RG_LIST" | while read -r rg; do
        if [[ -n "$rg" ]]; then
          echo "  - Deleting resource group: $rg"
          az group delete --name "$rg" --yes --no-wait 2>/dev/null || true
        fi
      done
      sleep 2
    else
      echo "  No resource groups to clean up"
    fi
  fi

  if [[ ${PURGE_DOCKER} == "1" ]]; then
    # Cleanup Docker resources after each test to free up disk space
    echo "Cleaning up Docker resources..."
    docker system prune -af --volumes || true
    echo ""
  fi
done

echo "All samples completed successfully!"
