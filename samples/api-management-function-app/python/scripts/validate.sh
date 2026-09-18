#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
FUNCTION_APP_NAME="${PREFIX}-inventory-functionapp-${SUFFIX}"
APIM_NAME="${PREFIX}-inventory-apim-${SUFFIX}"
APIM_API_VERSION='2022-08-01'
API_ID='inventory-api'
API_PATH='inventory'
APIM_SUBSCRIPTION_ID='partner-subscription'
RATE_LIMIT_CALLS=10
BODY_FILE='/tmp/inventory_body.json'
HEADERS_FILE='/tmp/inventory_headers.txt'

FAILED=0

# Retrieve the API Management service
APIM_ID=$(az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)

if [[ -z "$APIM_ID" ]]; then
	echo "Failed to retrieve the [$APIM_NAME] API Management service; run scripts/deploy.sh first. Exiting."
	exit 1
fi

# Resolve the two hosts. The emulator's Function App and gateway answer on plain HTTP under their
# own hostnames; on Azure both are HTTPS. The emulator also reports Azure's *.azure-api.net address
# in gatewayUrl, but that name only resolves once LocalStack's DNS is in front of the machine, so
# the gateway is called through its local alias instead.
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
FUNCTION_APP_HOSTNAME=$(az functionapp show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query defaultHostName --output tsv)

if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	BACKEND_URL="http://$FUNCTION_APP_HOSTNAME/api"
	GATEWAY_URL="http://${APIM_NAME}.apim.azure.localhost.localstack.cloud:4566"
else
	BACKEND_URL="https://$FUNCTION_APP_HOSTNAME/api"
	GATEWAY_URL=$(az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP_NAME --query gatewayUrl --output tsv)
fi
API_URL="$GATEWAY_URL/$API_PATH"
echo "Backend URL: $BACKEND_URL"
echo "Gateway URL: $API_URL"

# 1. Wait for the Function App: the zip deployment is asynchronous and the host takes a moment to
# start. A 401 is the answer we want from a direct call: the backend refuses anything that does
# not carry the shared secret, so the gateway is the only way in.
echo "Waiting for the [$FUNCTION_APP_NAME] function app to answer..."
BACKEND_STATUS=""
for i in $(seq 1 60); do
	BACKEND_STATUS=$(curl -s -m 10 -o /dev/null -w "%{http_code}" "$BACKEND_URL/items")
	[[ "$BACKEND_STATUS" == "401" ]] && break
	sleep 5
done
echo "Direct call to the backend without the shared secret: HTTP $BACKEND_STATUS"
if [[ "$BACKEND_STATUS" == "401" ]]; then
	echo "The backend refuses direct calls"
else
	echo "Expected the backend to answer 401 to a direct call"
	FAILED=1
fi

# 2. The OpenAPI import produced the operations.
echo "Listing the operations of the [$API_ID] API..."
OPERATIONS=$(az apim api operation list \
	--api-id $API_ID \
	--service-name $APIM_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query "[].name" \
	--output tsv | sort | tr '\n' ' ')
echo "Operations: $OPERATIONS"
for OPERATION in getItem listItems whoAmI; do
	if ! echo "$OPERATIONS" | grep -qw "$OPERATION"; then
		echo "Operation [$OPERATION] was not imported"
		FAILED=1
	fi
done

# 3. A call without a subscription key is refused with Azure's own message.
echo "Calling [$API_URL/items] without a subscription key..."
NO_KEY_STATUS=$(curl -s -m 10 -o "$BODY_FILE" -w "%{http_code}" "$API_URL/items")
echo "HTTP $NO_KEY_STATUS: $(cat "$BODY_FILE")"
if [[ "$NO_KEY_STATUS" == "401" ]] && grep -q "missing subscription key" "$BODY_FILE"; then
	echo "Keyless calls are refused"
else
	echo "Expected 401 with the missing-subscription-key message"
	FAILED=1
fi

# 4. Take the partner subscription's key from the control plane. It is the only credential the
# client needs; the backend secret stays inside API Management.
echo "Reading the [$APIM_SUBSCRIPTION_ID] subscription key..."
KEY=$(az rest --method post \
	--url "$APIM_ID/subscriptions/$APIM_SUBSCRIPTION_ID/listSecrets?api-version=$APIM_API_VERSION" \
	--query primaryKey \
	--output tsv)
if [[ -z "$KEY" ]]; then
	echo "Failed to read the [$APIM_SUBSCRIPTION_ID] subscription key. Exiting."
	exit 1
fi
echo "Subscription key retrieved (${#KEY} characters)"

# 5. A wrong key is refused too, with a different message.
echo "Calling [$API_URL/items] with a wrong subscription key..."
BAD_KEY_STATUS=$(curl -s -m 10 -o "$BODY_FILE" -w "%{http_code}" -H "Ocp-Apim-Subscription-Key: not-a-real-key" "$API_URL/items")
echo "HTTP $BAD_KEY_STATUS: $(cat "$BODY_FILE")"
if [[ "$BAD_KEY_STATUS" == "401" ]] && grep -q "invalid subscription key" "$BODY_FILE"; then
	echo "Wrong keys are refused"
else
	echo "Expected 401 with the invalid-subscription-key message"
	FAILED=1
fi

# 6. listItems: the request is authorised, the policies run, and the Function App answers.
echo "Calling [$API_URL/items] with the subscription key..."
LIST_STATUS=$(curl -s -m 20 -o "$BODY_FILE" -D "$HEADERS_FILE" -w "%{http_code}" -H "Ocp-Apim-Subscription-Key: $KEY" "$API_URL/items")
cat "$BODY_FILE"
echo
COUNT=$(jq -r '.count' "$BODY_FILE" 2>/dev/null)
if [[ "$LIST_STATUS" == "200" && "$COUNT" == "3" ]]; then
	echo "listItems answered 200 with $COUNT items"
else
	echo "Expected 200 with 3 items (got HTTP $LIST_STATUS, count=$COUNT)"
	FAILED=1
fi
if grep -qi "^x-served-by: Azure API Management" "$HEADERS_FILE"; then
	echo "The outbound policy added the X-Served-By header"
else
	echo "The X-Served-By header is missing from the response"
	FAILED=1
fi

# 7. getItem: the {id} template parameter is matched by the gateway and read by the backend. A
# 404 from the backend passes through the gateway untouched.
echo "Calling [$API_URL/items/2]..."
ITEM_STATUS=$(curl -s -m 20 -o "$BODY_FILE" -w "%{http_code}" -H "Ocp-Apim-Subscription-Key: $KEY" "$API_URL/items/2")
SKU=$(jq -r '.sku' "$BODY_FILE" 2>/dev/null)
echo "HTTP $ITEM_STATUS: $(jq -c . "$BODY_FILE" 2>/dev/null || cat "$BODY_FILE")"
if [[ "$ITEM_STATUS" == "200" && "$SKU" == "APIM-002" ]]; then
	echo "getItem answered 200 with the requested item"
else
	echo "Expected 200 with sku APIM-002 (got HTTP $ITEM_STATUS, sku=$SKU)"
	FAILED=1
fi
echo "Calling [$API_URL/items/99]..."
MISSING_STATUS=$(curl -s -m 20 -o "$BODY_FILE" -w "%{http_code}" -H "Ocp-Apim-Subscription-Key: $KEY" "$API_URL/items/99")
echo "HTTP $MISSING_STATUS: $(jq -c . "$BODY_FILE" 2>/dev/null || cat "$BODY_FILE")"
if [[ "$MISSING_STATUS" == "404" ]] && grep -q "No item with id 99" "$BODY_FILE"; then
	echo "The backend's 404 passes through the gateway"
else
	echo "Expected the backend's 404 for a missing item (got HTTP $MISSING_STATUS)"
	FAILED=1
fi

# 8. whoAmI: what reached the backend shows the policies at work. The shared secret arrived, the
# subscription key did not, and the backend was told which subscription is calling.
echo "Calling [$API_URL/whoami]..."
WHOAMI_STATUS=$(curl -s -m 20 -o "$BODY_FILE" -w "%{http_code}" -H "Ocp-Apim-Subscription-Key: $KEY" "$API_URL/whoami")
cat "$BODY_FILE"
echo
SECRET_RECEIVED=$(jq -r '.backend_secret_received' "$BODY_FILE" 2>/dev/null)
FORWARDED_KEY=$(jq -r '.headers["ocp-apim-subscription-key"] // "absent"' "$BODY_FILE" 2>/dev/null)
CALLER=$(jq -r '.headers["x-caller-subscription"] // ""' "$BODY_FILE" 2>/dev/null)
if [[ "$WHOAMI_STATUS" == "200" && "$SECRET_RECEIVED" == "true" ]]; then
	echo "The gateway injected the backend secret from the named value"
else
	echo "Expected the backend to receive the shared secret (got HTTP $WHOAMI_STATUS, backend_secret_received=$SECRET_RECEIVED)"
	FAILED=1
fi
if [[ "$FORWARDED_KEY" == "absent" ]]; then
	echo "The subscription key was stripped before the backend"
else
	echo "The subscription key reached the backend"
	FAILED=1
fi
if [[ "$CALLER" == "$APIM_SUBSCRIPTION_ID" ]]; then
	echo "The backend was told the calling subscription: $CALLER"
else
	echo "Expected X-Caller-Subscription to be [$APIM_SUBSCRIPTION_ID] (got: $CALLER)"
	FAILED=1
fi

# 9. A browser preflight is answered by the gateway itself, from the cors policy, without a key.
# On the emulator this is not yet observable: LocalStack answers CORS for every hostname it serves
# (its own origin allow-list, see EXTRA_CORS_ALLOWED_ORIGINS), the API Management gateway included,
# so the preflight never reaches the API's cors policy. Asserted against Azure only.
# TODO: assert this unconditionally once the emulator lets the gateway's cors policy answer.
echo "Sending a CORS preflight to [$API_URL/items]..."
PREFLIGHT_STATUS=$(curl -s -m 10 -o /dev/null -D "$HEADERS_FILE" -w "%{http_code}" \
	-X OPTIONS \
	-H "Origin: http://localhost:3000" \
	-H "Access-Control-Request-Method: GET" \
	"$API_URL/items")
ALLOW_ORIGIN=$(grep -i "^access-control-allow-origin:" "$HEADERS_FILE" | tr -d '\r')
echo "HTTP $PREFLIGHT_STATUS ${ALLOW_ORIGIN:-(no Access-Control-Allow-Origin header)}"
if [[ "$PREFLIGHT_STATUS" == "200" && -n "$ALLOW_ORIGIN" ]]; then
	echo "The preflight is answered by the gateway's cors policy"
elif [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	echo "Not asserted on the emulator: LocalStack's own CORS layer answered before the gateway's cors policy could"
else
	echo "Expected a 200 preflight response with Access-Control-Allow-Origin"
	FAILED=1
fi

# 10. A path that matches no operation gets Azure's 404 body.
echo "Calling [$API_URL/nothing-here]..."
UNKNOWN_STATUS=$(curl -s -m 10 -o "$BODY_FILE" -w "%{http_code}" -H "Ocp-Apim-Subscription-Key: $KEY" "$API_URL/nothing-here")
echo "HTTP $UNKNOWN_STATUS: $(cat "$BODY_FILE")"
if [[ "$UNKNOWN_STATUS" == "404" ]] && grep -q "Resource not found" "$BODY_FILE"; then
	echo "Unknown operations get the gateway's 404"
else
	echo "Expected the gateway's 404 for an unknown operation"
	FAILED=1
fi

# 11. The rate limit. The policy allows RATE_LIMIT_CALLS calls a minute per subscription; the calls
# above count towards it, and the loop below runs until the gateway answers 429 with a Retry-After.
# This check runs last on purpose: the subscription stays limited for the rest of the window.
echo "Calling [$API_URL/items] until the rate limit trips (limit: $RATE_LIMIT_CALLS calls a minute)..."
LIMITED=0
for i in $(seq 1 $((RATE_LIMIT_CALLS + 2))); do
	STATUS=$(curl -s -m 10 -o "$BODY_FILE" -D "$HEADERS_FILE" -w "%{http_code}" -H "Ocp-Apim-Subscription-Key: $KEY" "$API_URL/items")
	echo "  call $i: HTTP $STATUS"
	if [[ "$STATUS" == "429" ]]; then
		LIMITED=1
		break
	fi
done
if [[ $LIMITED == 1 ]]; then
	echo "Rate limit response: $(cat "$BODY_FILE")"
	RETRY_AFTER=$(grep -i "^retry-after:" "$HEADERS_FILE" | tr -d '\r' | awk '{print $2}')
	if [[ -n "$RETRY_AFTER" ]]; then
		echo "The rate limit tripped with Retry-After: $RETRY_AFTER seconds"
	else
		echo "The 429 response carries no Retry-After header"
		FAILED=1
	fi
else
	echo "The rate limit did not trip after $((RATE_LIMIT_CALLS + 2)) calls"
	FAILED=1
fi

if [[ $FAILED == 0 ]]; then
	echo "All validation checks passed"
else
	echo "Some validation checks failed"
fi
exit $FAILED
