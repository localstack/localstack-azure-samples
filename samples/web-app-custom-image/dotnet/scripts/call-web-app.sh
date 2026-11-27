#!/bin/bash
set -euo pipefail

PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
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

# The web app pulls its image and starts after the deployment, which doesn't wait for it: on Azure that can take a few
# minutes, so the call is tried again until the web app answers.
RETRY_COUNT="${RETRY_COUNT:-60}"
SLEEP="${SLEEP:-10}"
echo "Calling Web App using $APP_HOST_NAME..."
for ATTEMPT in $(seq 1 "$RETRY_COUNT"); do
	if curl --max-time 10 -fsS "http://$APP_HOST_NAME/api/status"; then
		echo ""
		exit 0
	fi
	if [ "$ATTEMPT" -lt "$RETRY_COUNT" ]; then
		echo "Attempt $ATTEMPT of $RETRY_COUNT: the web app didn't answer yet. Waiting [$SLEEP] seconds before retry..."
		sleep "$SLEEP"
	fi
done
echo "Error: the web app [$WEB_APP_NAME] didn't answer after $RETRY_COUNT attempts"
exit 1
