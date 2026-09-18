#!/bin/bash

# =============================================================================
# Removes everything scripts/deploy.sh created.
#
# Deleting the resource group is enough: the Front Door profile, its endpoint,
# origin groups, origins, routes and rule set, both Function Apps, their storage
# accounts and the shared App Service plan are all inside it.
# =============================================================================

PREFIX='local'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Deleting resource group [$RESOURCE_GROUP_NAME] and everything in it..."
az group delete \
	--name "$RESOURCE_GROUP_NAME" \
	--yes \
	--only-show-errors 1>/dev/null

if [[ $? -eq 0 ]]; then
	echo "Resource group [$RESOURCE_GROUP_NAME] deleted."
else
	echo "WARNING: could not delete resource group [$RESOURCE_GROUP_NAME] (it may not exist)."
fi

rm -f "$CURRENT_DIR"/../function/*.zip
echo "Removed local deployment artifacts."
