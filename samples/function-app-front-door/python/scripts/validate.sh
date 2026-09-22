#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
PRIMARY_FUNCTION_APP_NAME="${PREFIX}-catalog-primary-${SUFFIX}"
SECONDARY_FUNCTION_APP_NAME="${PREFIX}-catalog-secondary-${SUFFIX}"
PROFILE_NAME="${PREFIX}-catalog-afd-${SUFFIX}"
ENDPOINT_NAME="${PREFIX}-catalog-${SUFFIX}"
BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/front_door_body.XXXXXX")"
HEADERS_FILE="$(mktemp "${TMPDIR:-/tmp}/front_door_headers.XXXXXX")"
trap 'rm -f "$BODY_FILE" "$HEADERS_FILE"' EXIT

FAILED=0

# Retrieve the Front Door profile
PROFILE_ID=$(az afd profile show --profile-name $PROFILE_NAME --resource-group $RESOURCE_GROUP_NAME --query id --output tsv)

if [[ -z "$PROFILE_ID" ]]; then
	echo "Failed to retrieve the [$PROFILE_NAME] Front Door profile; run scripts/deploy.sh first. Exiting."
	exit 1
fi

# Resolve the addresses. The emulator serves both the Function Apps and the Front Door endpoint on
# plain HTTP under their own host names; on Azure both are HTTPS. The emulator also reports Azure's
# *.azurefd.net address in hostName, but that name only resolves once LocalStack's DNS is in front
# of the machine, so the endpoint is called through its local alias instead.
ENVIRONMENT_NAME=$(az account show --query environmentName --output tsv)
PRIMARY_HOST_NAME=$(az functionapp show --name $PRIMARY_FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query defaultHostName --output tsv)
SECONDARY_HOST_NAME=$(az functionapp show --name $SECONDARY_FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME --query defaultHostName --output tsv)

if [[ "$ENVIRONMENT_NAME" == "LocalStack" ]]; then
	PRIMARY_URL="http://$PRIMARY_HOST_NAME/api"
	SECONDARY_URL="http://$SECONDARY_HOST_NAME/api"
	ENDPOINT_URL="http://${ENDPOINT_NAME}.afd.azure.localhost.localstack.cloud:4566"
	# Local changes take effect at once; on Azure they are rolled out across the edge.
	PROPAGATION_ATTEMPTS=12
else
	PRIMARY_URL="https://$PRIMARY_HOST_NAME/api"
	SECONDARY_URL="https://$SECONDARY_HOST_NAME/api"
	ENDPOINT_HOST_NAME=$(az afd endpoint show --endpoint-name $ENDPOINT_NAME --profile-name $PROFILE_NAME --resource-group $RESOURCE_GROUP_NAME --query hostName --output tsv)
	ENDPOINT_URL="https://$ENDPOINT_HOST_NAME"
	# Microsoft budgets up to ten minutes for a purge to reach every PoP, and the loops that wait
	# on one sleep five seconds, so ten minutes is 120 attempts. The endpoint-serving loop sleeps
	# ten, which gives a new endpoint twenty minutes to come up.
	PROPAGATION_ATTEMPTS=120
fi

echo "Primary origin:  $PRIMARY_URL"
echo "Secondary origin: $SECONDARY_URL"
echo "Front Door endpoint: $ENDPOINT_URL"

# 1. Wait for both Function Apps. The zip deployment is asynchronous and the host takes a moment to
# start; Front Door caches the outcome of its health probe, so an origin that is not up before the
# first request through the endpoint stays out of rotation until the next probe interval.
wait_for_origin() {
	local NAME=$1
	local URL=$2
	local STATUS=''

	echo "Waiting for the [$NAME] function app to answer..."
	for i in $(seq 1 60); do
		STATUS=$(curl -s -m 10 -o "$BODY_FILE" -w "%{http_code}" "$URL/health")
		[[ "$STATUS" == "200" ]] && break
		sleep 5
	done
	if [[ "$STATUS" == "200" ]]; then
		echo "[$NAME] answers its health probe path: $(cat "$BODY_FILE" | tr -d '\n')"
	else
		echo "[$NAME] never answered $URL/health (last status: $STATUS)"
		FAILED=1
	fi
}

wait_for_origin "$PRIMARY_FUNCTION_APP_NAME" "$PRIMARY_URL"
wait_for_origin "$SECONDARY_FUNCTION_APP_NAME" "$SECONDARY_URL"

if [[ $FAILED != 0 ]]; then
	echo "The origins are not serving; nothing behind Front Door can be checked. Exiting."
	exit 1
fi

# The origins answer HEAD as well as GET, which is what the health probe sends.
HEAD_STATUS=$(curl -s -m 10 -o /dev/null -w "%{http_code}" -I "$PRIMARY_URL/health")
echo "HEAD on the probe path: HTTP $HEAD_STATUS"
if [[ "$HEAD_STATUS" == "200" ]]; then
	echo "The origin answers the probe method Front Door uses"
else
	echo "Expected the origin to answer HEAD with 200; Front Door would mark it unhealthy"
	FAILED=1
fi

# 2. Wait for the endpoint itself, then read the catalog through Front Door.
echo "Waiting for the [$ENDPOINT_NAME] endpoint to serve..."
ENDPOINT_STATUS=''
for i in $(seq 1 $PROPAGATION_ATTEMPTS); do
	ENDPOINT_STATUS=$(curl -s -m 20 -o "$BODY_FILE" -D "$HEADERS_FILE" -w "%{http_code}" "$ENDPOINT_URL/catalog/1")
	[[ "$ENDPOINT_STATUS" == "200" ]] && break
	sleep 10
done
echo "HTTP $ENDPOINT_STATUS: $(cat "$BODY_FILE" | tr -d '\n')"

if [[ "$ENDPOINT_STATUS" != "200" ]]; then
	echo "The endpoint never served the catalog; the checks below cannot run. Exiting."
	exit 1
fi

SKU=$(jq -r '.item.sku' "$BODY_FILE" 2>/dev/null)
ORIGIN=$(jq -r '.origin' "$BODY_FILE" 2>/dev/null)
RECEIVED_PATH=$(jq -r '.path' "$BODY_FILE" 2>/dev/null)
if [[ "$SKU" == "AFD-001" ]]; then
	echo "The catch-all route reached the catalog"
else
	echo "Expected catalog item AFD-001 through the endpoint (got sku=$SKU)"
	FAILED=1
fi
if [[ "$ORIGIN" == "primary" ]]; then
	echo "The priority-1 origin answered"
else
	echo "Expected the priority-1 origin to answer (got: $ORIGIN)"
	FAILED=1
fi
# The route's origin path puts the Functions route prefix back on, so the client never sends it.
if [[ "$RECEIVED_PATH" == "/api/catalog/1" ]]; then
	echo "The route's origin path prefixed the request to the origin: $RECEIVED_PATH"
else
	echo "Expected the origin to be asked for /api/catalog/1 (got: $RECEIVED_PATH)"
	FAILED=1
fi

# 3. The rules engine stamped the response on its way out.
SERVED_BY=$(grep -i "^x-served-by:" "$HEADERS_FILE" | tr -d '\r' | awk '{print $2}')
echo "Response header added by the rule set: ${SERVED_BY:-(none)}"
if [[ "$SERVED_BY" == "front-door" ]]; then
	echo "The ModifyResponseHeader rule ran"
else
	echo "Expected X-Served-By: front-door from the rule set"
	FAILED=1
fi

# Every response carries Front Door's own reference id, which support asks for.
if grep -qi "^x-azure-ref:" "$HEADERS_FILE"; then
	echo "The response carries an X-Azure-Ref reference id"
else
	echo "Expected an X-Azure-Ref header on the response"
	FAILED=1
fi

# 4. A more specific route wins over the catch-all, and sends the request to a different origin
# group. Both routes are linked to the same endpoint.
echo "Calling [$ENDPOINT_URL/status]..."
STATUS_CODE=$(curl -s -m 20 -o "$BODY_FILE" -w "%{http_code}" "$ENDPOINT_URL/status")
STATUS_ORIGIN=$(jq -r '.origin' "$BODY_FILE" 2>/dev/null)
echo "HTTP $STATUS_CODE: $(cat "$BODY_FILE" | tr -d '\n')"
if [[ "$STATUS_CODE" == "200" && "$STATUS_ORIGIN" == "secondary" ]]; then
	echo "/status matched the specific route and went to the other origin group"
else
	echo "Expected /status to be served by the secondary origin (got HTTP $STATUS_CODE, origin=$STATUS_ORIGIN)"
	FAILED=1
fi

# 5. The UrlRewrite rule: the client asks for /shop/2, the origin is asked for /api/catalog/2.
echo "Calling [$ENDPOINT_URL/shop/2]..."
SHOP_STATUS=$(curl -s -m 20 -o "$BODY_FILE" -w "%{http_code}" "$ENDPOINT_URL/shop/2")
SHOP_PATH=$(jq -r '.path' "$BODY_FILE" 2>/dev/null)
SHOP_SKU=$(jq -r '.item.sku' "$BODY_FILE" 2>/dev/null)
echo "HTTP $SHOP_STATUS: origin path $SHOP_PATH, sku $SHOP_SKU"
if [[ "$SHOP_STATUS" == "200" && "$SHOP_PATH" == "/api/catalog/2" && "$SHOP_SKU" == "AFD-002" ]]; then
	echo "The UrlRewrite rule rewrote /shop to /catalog before the origin call"
else
	echo "Expected /shop/2 to reach the origin as /api/catalog/2 with sku AFD-002"
	FAILED=1
fi

# 6. The UrlRedirect rule answers at the edge: the origin is never called.
echo "Calling [$ENDPOINT_URL/legacy]..."
REDIRECT_STATUS=$(curl -s -m 20 -o /dev/null -D "$HEADERS_FILE" -w "%{http_code}" "$ENDPOINT_URL/legacy")
LOCATION=$(grep -i "^location:" "$HEADERS_FILE" | tr -d '\r' | awk '{print $2}')
echo "HTTP $REDIRECT_STATUS -> ${LOCATION:-(no Location header)}"
if [[ "$REDIRECT_STATUS" == "302" && "$LOCATION" == */status ]]; then
	echo "The UrlRedirect rule answered at the edge"
else
	echo "Expected a 302 to /status from the rule set"
	FAILED=1
fi

# 7. Caching. The catalog response carries a Cache-Control the edge can honour, so the second
# request is served from the cache. Azure reports this as TCP_HIT and the emulator as HIT, so the
# check reads the word rather than the whole value.
#
# The first request has to start from an empty cache to mean anything, and an earlier run of this
# script against the same endpoint would have left entries behind, so purge before measuring.
purge_catalog() {
	az afd endpoint purge \
		--endpoint-name $ENDPOINT_NAME \
		--profile-name $PROFILE_NAME \
		--resource-group $RESOURCE_GROUP_NAME \
		--content-paths '/catalog/*' 1>/dev/null

	if [[ $? != 0 ]]; then
		echo "Failed to purge the endpoint"
		FAILED=1
	fi
}

echo "Purging /catalog/* so the cache starts empty..."
purge_catalog

echo "Requesting [$ENDPOINT_URL/catalog/3] twice..."
curl -s -m 20 -o /dev/null -D "$HEADERS_FILE" "$ENDPOINT_URL/catalog/3"
FIRST_CACHE=$(grep -i "^x-cache:" "$HEADERS_FILE" | tr -d '\r' | awk '{print $2}')
if echo "$FIRST_CACHE" | grep -qi "hit"; then
	echo "Expected the first request after a purge to reach the origin (got: $FIRST_CACHE)"
	FAILED=1
fi
# Each Front Door edge site manages its own cache and a request may be served by a different
# one, so a second request that lands on a cold PoP is a miss rather than a failure. Locally
# there is one cache and the first attempt always hits.
SECOND_CACHE=''
for i in $(seq 1 $PROPAGATION_ATTEMPTS); do
	curl -s -m 20 -o "$BODY_FILE" -D "$HEADERS_FILE" "$ENDPOINT_URL/catalog/3"
	SECOND_CACHE=$(grep -i "^x-cache:" "$HEADERS_FILE" | tr -d '\r' | awk '{print $2}')
	echo "$SECOND_CACHE" | grep -qi "hit" && break
	sleep 5
done
CACHE_AGE=$(grep -i "^age:" "$HEADERS_FILE" | tr -d '\r' | awk '{print $2}')
echo "First request: X-Cache: ${FIRST_CACHE:-(none)}; second request: X-Cache: ${SECOND_CACHE:-(none)} Age: ${CACHE_AGE:-(none)}"
if echo "$SECOND_CACHE" | grep -qi "hit"; then
	echo "The second request was served from the edge cache"
else
	echo "Expected the second request to be a cache hit (got: ${SECOND_CACHE:-none})"
	FAILED=1
fi

# A purge empties the cache for the paths it names, so the next request goes to the origin again.
echo "Purging /catalog/* from the endpoint..."
purge_catalog

PURGED_CACHE=''
for i in $(seq 1 $PROPAGATION_ATTEMPTS); do
	curl -s -m 20 -o /dev/null -D "$HEADERS_FILE" "$ENDPOINT_URL/catalog/3"
	PURGED_CACHE=$(grep -i "^x-cache:" "$HEADERS_FILE" | tr -d '\r' | awk '{print $2}')
	echo "$PURGED_CACHE" | grep -qi "hit" || break
	sleep 5
done
echo "After the purge: X-Cache: ${PURGED_CACHE:-(none)}"
if echo "$PURGED_CACHE" | grep -qi "hit"; then
	echo "Expected the purged path to be fetched from the origin again"
	FAILED=1
else
	echo "The purged path was fetched from the origin again"
fi

# A response the origin marks no-store is never cached, however often it is asked for.
curl -s -m 20 -o /dev/null -D "$HEADERS_FILE" "$ENDPOINT_URL/whoami"
curl -s -m 20 -o "$BODY_FILE" -D "$HEADERS_FILE" "$ENDPOINT_URL/whoami"
NOSTORE_CACHE=$(grep -i "^x-cache:" "$HEADERS_FILE" | tr -d '\r' | awk '{print $2}')
echo "A no-store response: X-Cache: ${NOSTORE_CACHE:-(none)}"
if echo "$NOSTORE_CACHE" | grep -qi "hit"; then
	echo "A response the origin marked no-store was served from the cache"
	FAILED=1
else
	echo "The no-store response was not cached"
fi

# 8. What Front Door tells the origin about the client and about itself.
echo "Reading [$ENDPOINT_URL/whoami]..."
jq -r '.front_door_headers' "$BODY_FILE" 2>/dev/null
FORWARDED_HOST=$(jq -r '.front_door_headers["x-forwarded-host"] // ""' "$BODY_FILE" 2>/dev/null)
CLIENT_IP=$(jq -r '.front_door_headers["x-azure-clientip"] // ""' "$BODY_FILE" 2>/dev/null)
FDID=$(jq -r '.front_door_headers["x-azure-fdid"] // ""' "$BODY_FILE" 2>/dev/null)
if [[ -n "$FORWARDED_HOST" && "$ENDPOINT_URL" == *"$FORWARDED_HOST"* ]]; then
	echo "The origin was told which host the client asked for: $FORWARDED_HOST"
else
	echo "Expected X-Forwarded-Host to name the endpoint (got: ${FORWARDED_HOST:-none})"
	FAILED=1
fi
if [[ -n "$CLIENT_IP" ]]; then
	echo "The origin was told the client's address: $CLIENT_IP"
else
	echo "Expected an X-Azure-ClientIP header at the origin"
	FAILED=1
fi
# The profile's own id, which an origin uses to refuse traffic that did not come through it.
if [[ -n "$FDID" ]]; then
	echo "The origin was told which Front Door profile called it: $FDID"
else
	echo "Expected an X-Azure-FDID header at the origin"
	FAILED=1
fi

# 9. Priority is a strict tier: while the priority-1 origin is healthy the standby gets nothing.
# /whoami is not cached, so each of these requests reaches an origin.
echo "Sending ten requests to check origin selection..."
# Counting the primary's answers rather than only the standby's: a failed request produces no
# origin name at all, which would otherwise read as "the standby answered none of them".
PRIMARY_ANSWERS=0
STANDBY_ANSWERS=0
for i in $(seq 1 10); do
	WHO=$(curl -s -m 20 "$ENDPOINT_URL/whoami" | jq -r '.origin' 2>/dev/null)
	[[ "$WHO" == "primary" ]] && PRIMARY_ANSWERS=$((PRIMARY_ANSWERS + 1))
	[[ "$WHO" == "secondary" ]] && STANDBY_ANSWERS=$((STANDBY_ANSWERS + 1))
done
if [[ $PRIMARY_ANSWERS == 10 ]]; then
	echo "All ten requests were answered by the priority-1 origin"
else
	echo "Expected ten answers from the priority-1 origin (got $PRIMARY_ANSWERS; the standby answered $STANDBY_ANSWERS)"
	FAILED=1
fi

# 10. The origin's own error passes through the edge untouched.
MISSING_STATUS=$(curl -s -m 20 -o "$BODY_FILE" -w "%{http_code}" "$ENDPOINT_URL/catalog/99")
echo "HTTP $MISSING_STATUS: $(cat "$BODY_FILE" | tr -d '\n')"
if [[ "$MISSING_STATUS" == "404" ]] && grep -q "No catalog item 99" "$BODY_FILE"; then
	echo "The origin's 404 passes through Front Door"
else
	echo "Expected the origin's 404 for a missing catalog item (got HTTP $MISSING_STATUS)"
	FAILED=1
fi

# 11. A disabled endpoint stops serving, and serves again once it is enabled. This check runs last
# because it takes the endpoint out of service while it runs.
echo "Disabling the [$ENDPOINT_NAME] endpoint..."
az afd endpoint update \
	--endpoint-name $ENDPOINT_NAME \
	--profile-name $PROFILE_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--enabled-state Disabled 1>/dev/null

DISABLED_STATUS=''
for i in $(seq 1 $PROPAGATION_ATTEMPTS); do
	DISABLED_STATUS=$(curl -s -m 20 -o /dev/null -w "%{http_code}" "$ENDPOINT_URL/status")
	[[ "$DISABLED_STATUS" != "200" ]] && break
	sleep 5
done
echo "A disabled endpoint answers: HTTP $DISABLED_STATUS"
if [[ "$DISABLED_STATUS" != "200" ]]; then
	echo "The disabled endpoint stopped serving"
else
	echo "Expected the disabled endpoint to stop serving"
	FAILED=1
fi

echo "Enabling the [$ENDPOINT_NAME] endpoint again..."
az afd endpoint update \
	--endpoint-name $ENDPOINT_NAME \
	--profile-name $PROFILE_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--enabled-state Enabled 1>/dev/null

ENABLED_STATUS=''
for i in $(seq 1 $PROPAGATION_ATTEMPTS); do
	ENABLED_STATUS=$(curl -s -m 20 -o /dev/null -w "%{http_code}" "$ENDPOINT_URL/status")
	[[ "$ENABLED_STATUS" == "200" ]] && break
	sleep 5
done
echo "The re-enabled endpoint answers: HTTP $ENABLED_STATUS"
if [[ "$ENABLED_STATUS" == "200" ]]; then
	echo "The endpoint serves again"
else
	echo "Expected the re-enabled endpoint to serve again"
	FAILED=1
fi

if [[ $FAILED == 0 ]]; then
	echo "All validation checks passed"
else
	echo "Some validation checks failed"
fi
exit $FAILED
