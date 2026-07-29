#!/bin/bash

# =============================================================================
# Removes everything scripts/deploy.sh created.
#
# Deleting the resource group is enough: Event Hubs, Storage, the Event Grid
# system topic and the Function App all live inside it.
# =============================================================================

PREFIX='local'
RESOURCE_GROUP_NAME="${PREFIX}-ehgrid-rg"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Deleting resource group [$RESOURCE_GROUP_NAME] and everything in it..."
if az group delete --name "$RESOURCE_GROUP_NAME" --yes --only-show-errors 1>/dev/null; then
	echo "Resource group [$RESOURCE_GROUP_NAME] deleted."
else
	echo "WARNING: could not delete resource group [$RESOURCE_GROUP_NAME] (it may not exist)."
fi

rm -f "$CURRENT_DIR/.deployment-env" "$CURRENT_DIR"/*.zip
echo "Removed local deployment artifacts."
