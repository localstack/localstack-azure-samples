#!/usr/bin/env bash
set -uo pipefail

# Cleanup script to stop and remove LocalStack containers and revert CLI configurations.

echo "Stopping LocalStack..."
localstack stop || true

echo "Killing any lingering LocalStack-related containers..."
# Kill the main container if it didn't stop
docker stop localstack-main >/dev/null 2>&1 || true
docker rm localstack-main >/dev/null 2>&1 || true

# Kill any containers started by LocalStack (e.g., function app sidecars)
# These usually have labels or specific naming conventions, but a safe bet is to look for those with localstack in the name or created by the localstack network
CONTAINERS=$(docker ps -a --filter "name=localstack" --filter "name=ls-" -q)
if [ -n "$CONTAINERS" ]; then
    echo "Stopping sidecar containers..."
    docker stop $CONTAINERS >/dev/null 2>&1 || true
    docker rm $CONTAINERS >/dev/null 2>&1 || true
fi

echo "Cleaning up Docker networks..."
docker network prune -f >/dev/null 2>&1 || true

echo "Reverting Azure CLI configuration..."
# Switch back to AzureCloud if LocalStack was the current cloud
CURRENT_CLOUD=$(az cloud show --query name -o tsv 2>/dev/null || echo "")
if [ "$CURRENT_CLOUD" == "LocalStack" ]; then
    az cloud set -n AzureCloud --only-show-errors || true
fi

# Optionally unregister the LocalStack cloud
# az cloud unregister -n LocalStack --only-show-errors || true

echo "Cleanup complete!"
echo "Note: LocalStack persistent data in ~/.localstack/volume was NOT removed."
echo "To remove it, run: rm -rf ~/.localstack/volume"
