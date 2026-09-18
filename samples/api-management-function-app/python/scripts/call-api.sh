#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
APIM_NAME="${PREFIX}-inventory-apim-${SUFFIX}"
APIM_API_VERSION='2022-08-01'
API_PATH='inventory'
APIM_SUBSCRIPTION_ID='partner-subscription'
BODY_FILE='/tmp/inventory_call.json'
HEADERS_FILE='/tmp/inventory_call_headers.txt'

# Retrieve the API Management service
echo "Retrieving the [$APIM_NAME] API Management service..."
APIM_ID=$(az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)

if [[ -n "$APIM_ID" ]]; then
	echo "[$APIM_NAME] API Management service successfully retrieved"
else
	echo "Failed to retrieve the [$APIM_NAME] API Management service"
	exit 1
fi

# Where the gateway answers: Azure's gatewayUrl, or the emulator's local alias (the emulator also
# claims the *.azure-api.net name, but it only resolves once LocalStack's DNS is in front of the machine)
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	GATEWAY_URL="http://${APIM_NAME}.apim.azure.localhost.localstack.cloud:4566"
else
	GATEWAY_URL=$(az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME --query gatewayUrl --output tsv)
fi
API_URL="$GATEWAY_URL/$API_PATH"

# Retrieve the subscription key
echo "Reading the [$APIM_SUBSCRIPTION_ID] subscription key..."
KEY=$(az rest --method post \
	--url "$APIM_ID/subscriptions/$APIM_SUBSCRIPTION_ID/listSecrets?api-version=$APIM_API_VERSION" \
	--query primaryKey \
	--output tsv)

if [[ -n "$KEY" ]]; then
	echo "[$APIM_SUBSCRIPTION_ID] subscription key successfully retrieved"
else
	echo "Failed to retrieve the [$APIM_SUBSCRIPTION_ID] subscription key"
	exit 1
fi

# Call the gateway. The API allows ten calls a minute per subscription, so a run right after
# validate.sh may be told to wait: honour the Retry-After the gateway sends and try once more.
call_api() {
	local url="$1"
	STATUS=$(curl -s -m 20 -o "$BODY_FILE" -D "$HEADERS_FILE" -w "%{http_code}" -H "Ocp-Apim-Subscription-Key: $KEY" "$url")
	if [[ "$STATUS" == "429" ]]; then
		RETRY_AFTER=$(grep -i "^retry-after:" "$HEADERS_FILE" | tr -d '\r' | awk '{print $2}')
		RETRY_AFTER=${RETRY_AFTER:-5}
		[[ $RETRY_AFTER -lt 1 ]] && RETRY_AFTER=1
		[[ $RETRY_AFTER -gt 60 ]] && RETRY_AFTER=60
		echo "Rate limited by the gateway; waiting $RETRY_AFTER seconds as asked..."
		sleep "$RETRY_AFTER"
		STATUS=$(curl -s -m 20 -o "$BODY_FILE" -D "$HEADERS_FILE" -w "%{http_code}" -H "Ocp-Apim-Subscription-Key: $KEY" "$url")
	fi
}

echo "Calling [$API_URL/items]..."
call_api "$API_URL/items"

if [[ "$STATUS" == "200" ]]; then
	echo "[$API_URL/items] successfully returned [$STATUS]:"
	jq . "$BODY_FILE"
else
	echo "[$API_URL/items] returned [$STATUS]: $(cat "$BODY_FILE")"
	exit 1
fi

echo "Calling [$API_URL/items/2]..."
call_api "$API_URL/items/2"

if [[ "$STATUS" == "200" ]]; then
	echo "[$API_URL/items/2] successfully returned [$STATUS]:"
	jq . "$BODY_FILE"
else
	echo "[$API_URL/items/2] returned [$STATUS]: $(cat "$BODY_FILE")"
	exit 1
fi

echo "Response header added by the gateway's outbound policy: $(grep -i "^x-served-by:" "$HEADERS_FILE" | tr -d '\r')"
