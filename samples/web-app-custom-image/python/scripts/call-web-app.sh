#!/bin/bash
set -euo pipefail

PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"

get_docker_container_name_by_prefix() {
	local app_prefix="$1"
	docker ps --format "{{.Names}}" | grep "^${app_prefix}" | head -1
}

get_docker_container_port_mapping() {
	local container_name="$1"
	local container_port="$2"
	docker inspect -f "{{(index (index .NetworkSettings.Ports \"${container_port}/tcp\") 0).HostPort}}" "$container_name"
}

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
curl -fsS "http://$APP_HOST_NAME/api/status"
echo ""
