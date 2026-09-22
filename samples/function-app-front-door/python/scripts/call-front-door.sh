#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
PROFILE_NAME="${PREFIX}-catalog-afd-${SUFFIX}"
ENDPOINT_NAME="${PREFIX}-catalog-${SUFFIX}"
BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/front_door_call.XXXXXX")"
HEADERS_FILE="$(mktemp "${TMPDIR:-/tmp}/front_door_call_headers.XXXXXX")"
trap 'rm -f "$BODY_FILE" "$HEADERS_FILE"' EXIT

# Retrieve the Front Door profile
echo "Retrieving the [$PROFILE_NAME] Front Door profile..."
PROFILE_ID=$(az afd profile show --profile-name $PROFILE_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)

if [[ -n "$PROFILE_ID" ]]; then
	echo "[$PROFILE_NAME] Front Door profile successfully retrieved"
else
	echo "Failed to retrieve the [$PROFILE_NAME] Front Door profile"
	exit 1
fi

# Where the endpoint answers: Azure's hostName, or the emulator's local alias (the emulator also
# claims the *.azurefd.net name, but it only resolves once LocalStack's DNS is in front of the machine)
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	ENDPOINT_URL="http://${ENDPOINT_NAME}.afd.azure.localhost.localstack.cloud:4566"
else
	ENDPOINT_HOST_NAME=$(az afd endpoint show --endpoint-name $ENDPOINT_NAME --profile-name $PROFILE_NAME --resource-group $RESOURCE_GROUP_NAME --query hostName --output tsv)
	ENDPOINT_URL="https://$ENDPOINT_HOST_NAME"
fi

# Call the endpoint and report what the edge did with the request
call_endpoint() {
	local PATH_TO_CALL="$1"
	STATUS=$(curl -s -m 20 -o "$BODY_FILE" -D "$HEADERS_FILE" -w "%{http_code}" "$ENDPOINT_URL$PATH_TO_CALL")
	CACHE=$(grep -i "^x-cache:" "$HEADERS_FILE" | tr -d '\r' | awk '{print $2}')
	SERVED_BY=$(grep -i "^x-served-by:" "$HEADERS_FILE" | tr -d '\r' | awk '{print $2}')
	LOCATION=$(grep -i "^location:" "$HEADERS_FILE" | tr -d '\r' | awk '{print $2}')
}

echo "Calling [$ENDPOINT_URL/catalog/1]..."
call_endpoint /catalog/1

if [[ "$STATUS" == "200" ]]; then
	jq . "$BODY_FILE"
	echo "Cache status: ${CACHE:-(none)}, stamped by the rule set: ${SERVED_BY:-(none)}"
else
	echo "[$ENDPOINT_URL/catalog/1] returned [$STATUS]: $(cat "$BODY_FILE")"
	exit 1
fi

echo "Calling it again, to be served from the edge cache..."
call_endpoint /catalog/1
echo "Cache status: ${CACHE:-(none)}"

echo "Calling [$ENDPOINT_URL/shop/3], which the rules engine rewrites to /catalog/3..."
call_endpoint /shop/3

if [[ "$STATUS" == "200" ]]; then
	echo "The origin was asked for $(jq -r '.path' "$BODY_FILE") and answered with $(jq -r '.item.name' "$BODY_FILE")"
else
	echo "[$ENDPOINT_URL/shop/3] returned [$STATUS]: $(cat "$BODY_FILE")"
	exit 1
fi

echo "Calling [$ENDPOINT_URL/legacy], which the rules engine redirects..."
call_endpoint /legacy
echo "Answered [$STATUS] at the edge, pointing at ${LOCATION:-(no Location header)}"

echo "Calling [$ENDPOINT_URL/whoami], which reports what the origin received..."
call_endpoint /whoami

if [[ "$STATUS" == "200" ]]; then
	jq . "$BODY_FILE"
else
	echo "[$ENDPOINT_URL/whoami] returned [$STATUS]: $(cat "$BODY_FILE")"
	exit 1
fi
