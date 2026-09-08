#!/bin/bash
set -euo pipefail

PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"

APP_HOST_NAME=$(az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "defaultHostName" \
	--output tsv \
	--only-show-errors)

if [ -z "$APP_HOST_NAME" ]; then
	echo "Failed to retrieve Web App hostname."
	exit 1
fi

echo "Web App hostname: $APP_HOST_NAME"

echo "Calling Web App using $APP_HOST_NAME..."
curl --max-time 10 -fsS "http://$APP_HOST_NAME/api/status"
echo ""
