#!/usr/bin/env bash
set -euo pipefail

# Helper script to run all sample tests locally, replicating the CI environment.
# Requirements:
# - Docker
# - Python 3.12+
# - .NET 9.0+
# - Azure CLI
# - azlocal (pip install azlocal)
# - funclocal (pip install funclocal)
# - Azure Functions Core Tools (func)
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
command -v funclocal >/dev/null 2>&1 || { echo >&2 "funclocal is required but not installed. Run 'pip install funclocal'. Aborting."; exit 1; }
command -v func >/dev/null 2>&1 || { echo >&2 "Azure Functions Core Tools (func) is required but not installed. Aborting."; exit 1; }

if [ -z "${LOCALSTACK_AUTH_TOKEN:-}" ]; then
  echo "Error: LOCALSTACK_AUTH_TOKEN is not set. It is required for the Azure emulator."
  exit 1
fi

# 1. Start LocalStack
echo "Starting LocalStack Azure emulator..."
IMAGE_NAME=localstack/localstack-azure-alpha localstack start -d
localstack wait -t 60

# 2. Register LocalStack Cloud in az CLI
#echo "Registering LocalStack cloud profile..."
#az cloud register -n LocalStack \
#  --endpoint-resource-manager "http://localhost:4566" \
#  --suffix-storage-endpoint "localhost.localstack.cloud" \
#  --suffix-keyvault-dns ".localhost.localstack.cloud" \
#  --endpoint-active-directory "http://localhost:4566" \
#  --endpoint-gallery "http://localhost:4566" \
#  --endpoint-management "http://localhost:4566" || true

#az cloud set -n LocalStack
#az login --service-principal -u "ignored" -p "ignored" --tenant "ignored" --allow-no-subscriptions || true

# 3. Define Samples
SAMPLES=(
  "samples/function-app-front-door/python|bash scripts/deploy_all.sh --name-prefix testafd --use-localstack|"
  "samples/function-app-managed-identity/python|bash scripts/user-managed-identity.sh|bash scripts/test.sh"
  "samples/function-app-storage-http/dotnet|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/call-http-triggers.sh"
  "samples/web-app-cosmosdb-mongodb-api/python|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/call-web-app.sh"
  "samples/web-app-managed-identity/python|bash scripts/user-assigned.sh|bash scripts/validate.sh && bash scripts/call-web-app.sh"
  "samples/web-app-sql-database/python|bash scripts/deploy.sh|bash scripts/validate.sh && bash scripts/get-web-app-url.sh"
)

# 4. Run Samples
for item in "${SAMPLES[@]}"; do
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
