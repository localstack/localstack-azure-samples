#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
WEB_APP_NAME="${PREFIX}-urlshort-webapp-${SUFFIX}"

# Retrieve the web app host name
echo "Retrieving the host name of the [$WEB_APP_NAME] web app..."
WEB_APP_HOSTNAME=$(az webapp show \
	--name $WEB_APP_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--query defaultHostName \
	--output tsv)

if [[ -n "$WEB_APP_HOSTNAME" ]]; then
	echo "Host name [$WEB_APP_HOSTNAME] of the [$WEB_APP_NAME] web app successfully retrieved"
else
	echo "Failed to retrieve the host name of the [$WEB_APP_NAME] web app"
	exit 1
fi
WEB_APP_URL="http://$WEB_APP_HOSTNAME"

# Call the home page
echo "Calling the [$WEB_APP_NAME] web app home page at [$WEB_APP_URL]..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$WEB_APP_URL/")

if [[ "$HTTP_STATUS" == "200" ]]; then
	echo "Home page of the [$WEB_APP_NAME] web app successfully returned [$HTTP_STATUS]"
else
	echo "Home page of the [$WEB_APP_NAME] web app returned [$HTTP_STATUS]"
	exit 1
fi

# Shorten a URL and follow the redirect
echo "Shortening a URL through the [$WEB_APP_NAME] web app..."
RESPONSE=$(curl -s -X POST "$WEB_APP_URL/shorten" \
	-H "Content-Type: application/json" \
	-d '{"url": "https://docs.localstack.cloud/azure/"}')
CODE=$(echo "$RESPONSE" | jq -r .code)

if [[ -n "$CODE" && "$CODE" != "null" ]]; then
	echo "Short link [$CODE] successfully created"
else
	echo "Failed to create a short link"
	exit 1
fi

echo "Following the short link [$WEB_APP_URL/l/$CODE]..."
REDIRECT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$WEB_APP_URL/l/$CODE")

if [[ "$REDIRECT_STATUS" == "302" ]]; then
	echo "Short link [$CODE] successfully redirected with [$REDIRECT_STATUS]"
else
	# Emulator releases without the fix from localstack/localstack-pro#8135 follow the
	# redirect at the gateway instead of passing the 302 through; accept that as long
	# as the click was recorded on the link.
	# TODO: drop this fallback and assert the bare 302 unconditionally once the fix
	# from localstack/localstack-pro#8135 ships in the released emulator image.
	HITS=$(curl -s "$WEB_APP_URL/api/links/$CODE" | jq -r .hits)
	if [[ "$HITS" =~ ^[0-9]+$ && "$HITS" -ge 1 ]]; then
		echo "Short link [$CODE] returned [$REDIRECT_STATUS] (redirect followed by the emulator gateway) and the click was recorded (hits=$HITS)"
	else
		echo "Short link [$CODE] returned [$REDIRECT_STATUS] instead of a redirect and no click was recorded"
		exit 1
	fi
fi
