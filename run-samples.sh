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
# - azlocal & terraform-local (pip install azlocal terraform-local)
# - funclocal (pip install funclocal)
# - Azure Functions Core Tools (func)
# - jq & zip (sudo apt-get install jq zip)
# - MSSQL Tools (sqlcmd)
# - LOCALSTACK_AUTH_TOKEN environment variable

# 0. Load environment variables from .env file if it exists
if [ -f .env ]; then
  echo "Loading environment variables from .env file..."
  # Use a subshell to avoid exporting everything if not needed, 
  # but here we actually want them in the environment.
  set -a
  source .env
  set +a
fi

# 1. Check for required tools
command -v localstack >/dev/null 2>&1 || { echo >&2 "localstack CLI is required but not installed. Aborting."; exit 1; }
command -v az >/dev/null 2>&1 || { echo >&2 "az CLI is required but not installed. Aborting."; exit 1; }
command -v azlocal >/dev/null 2>&1 || { echo >&2 "azlocal is required but not installed. Run 'pip install azlocal'. Aborting."; exit 1; }
command -v funclocal >/dev/null 2>&1 || { echo >&2 "funclocal is required but not installed. Run 'pip install azlocal'. Aborting."; exit 1; }
command -v tflocal >/dev/null 2>&1 || { echo >&2 "tflocal is required but not installed. Run 'pip install terraform-local'. Aborting."; exit 1; }
command -v func >/dev/null 2>&1 || { echo >&2 "Azure Functions Core Tools (func) is required but not installed. Aborting."; exit 1; }

if [ -z "${LOCALSTACK_AUTH_TOKEN:-}" ]; then
  echo "Error: LOCALSTACK_AUTH_TOKEN is not set. It is required for the Azure emulator."
  exit 1
fi

# 1. Start LocalStack
if ! localstack status | grep -q "running"; then
  echo "Starting LocalStack Azure emulator..."
  IMAGE_NAME=localstack/localstack-azure-alpha localstack start -d
  localstack wait -t 60
else
  echo "LocalStack is already running."
fi


# 2. Define Samples
SAMPLES=(
  "samples/function-app-front-door/python|bash scripts/deploy_all.sh --name-prefix testafd --use-localstack|"
  "samples/function-app-managed-identity/python/terraform|bash deploy.sh|"
  "samples/function-app-storage-http/dotnet/terraform|bash deploy.sh|"
  "samples/web-app-cosmosdb-mongodb-api/python/terraform|bash deploy.sh|"
  "samples/web-app-managed-identity/python/terraform|bash deploy.sh|"
  "samples/web-app-sql-database/python/terraform|bash deploy.sh|"
)

# 3. Calculate Shard
TOTAL=${#SAMPLES[@]}
SHARD=${1:-1}
SPLITS=${2:-1}

COUNT=$(( TOTAL / SPLITS ))
START=$(( (SHARD - 1) * COUNT ))

if [ "$SHARD" -eq "$SPLITS" ]; then
  COUNT=$(( TOTAL - START ))
fi

echo "Running samples shard $SHARD of $SPLITS (index $START, count $COUNT)"

# 4. Run Samples
for (( i=START; i<START+COUNT; i++ )); do
  item="${SAMPLES[$i]}"
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
  
  popd > /dev/null
  echo "Completed: $path"
  echo ""
done

echo "All samples completed successfully!"
