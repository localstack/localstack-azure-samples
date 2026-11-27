#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
DEPLOYMENT_NAME='url-shortener'
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
WEBAPP_ZIPFILE='linklet_webapp.zip'
WORKER_ZIPFILE='linklet_worker.zip'
DEPLOY_RETRY_COUNT=3
DEPLOY_RETRY_SLEEP=30
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Get the current subscription
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

# Check if the resource group already exists
echo "Checking if [$RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_NAME] subscription..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No [$RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_NAME] subscription"
	echo "Creating [$RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_NAME] subscription..."

	az group create --name $RESOURCE_GROUP_NAME --location "$LOCATION" 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$RESOURCE_GROUP_NAME] resource group successfully created in the [$SUBSCRIPTION_NAME] subscription"
	else
		echo "Failed to create [$RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_NAME] subscription"
		exit 1
	fi
else
	echo "[$RESOURCE_GROUP_NAME] resource group already exists in the [$SUBSCRIPTION_NAME] subscription"
fi

# The deployment secrets, which main.bicepparam reads from the environment. The first run generates them; a second
# run keeps them, because the PostgreSQL server, the key vault and both apps already use them and the signing key
# signed the existing links: the first run saved them, with the PostgreSQL host, in the file it writes for
# scripts/validate.sh.
STATE_FILE="$CURRENT_DIR/../scripts/.last_deploy.${PREFIX}.env"
POSTGRES_SERVER_COUNT=$(az postgres flexible-server list --resource-group "$RESOURCE_GROUP_NAME" --query "length(@)" --output tsv --only-show-errors 2>/dev/null | tr -d '\r')
if [[ -f "$STATE_FILE" && ${POSTGRES_SERVER_COUNT:-0} -gt 0 ]]; then
	echo "Reusing the deployment secrets of the previous run from [$STATE_FILE]"
	# shellcheck disable=SC1090
	source "$STATE_FILE"
fi
export POSTGRES_ADMIN_PASSWORD="${POSTGRES_ADMIN_PASSWORD:-$(openssl rand -hex 10)}"
export SIGN_KEY="${SIGN_KEY:-$(openssl rand -hex 16)}"
export INTERNAL_TOKEN="${INTERNAL_TOKEN:-$(openssl rand -hex 12)}"

# Validate the Bicep template
echo "Validating the [$TEMPLATE] Bicep template..."
az deployment group validate \
	--resource-group $RESOURCE_GROUP_NAME \
	--template-file $TEMPLATE \
	--parameters $PARAMETERS \
	--parameters prefix=$PREFIX \
	suffix=$SUFFIX \
	--output none

if [[ $? == 0 ]]; then
	echo "[$TEMPLATE] Bicep template successfully validated"
else
	echo "Failed to validate the [$TEMPLATE] Bicep template"
	exit 1
fi

# Deploy the Bicep template
echo "Deploying the [$TEMPLATE] Bicep template..."
DEPLOYMENT_OUTPUTS=$(az deployment group create \
	--name $DEPLOYMENT_NAME \
	--resource-group $RESOURCE_GROUP_NAME \
	--template-file $TEMPLATE \
	--parameters $PARAMETERS \
	--parameters prefix=$PREFIX \
	suffix=$SUFFIX \
	--query properties.outputs)

if [[ $? == 0 ]]; then
	echo "[$TEMPLATE] Bicep template successfully deployed"
else
	echo "Failed to deploy the [$TEMPLATE] Bicep template"
	exit 1
fi

WEB_APP_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r .webAppName.value)
FUNCTION_APP_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r .functionAppName.value)
WEB_APP_HOSTNAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r .webAppHostName.value)
POSTGRES_HOST=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r .postgresHost.value)
POSTGRES_PORT=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r .postgresPort.value)

if [[ -z "$WEB_APP_NAME" || -z "$FUNCTION_APP_NAME" ]]; then
	echo "Web App Name or Function App Name is empty. Exiting."
	exit 1
fi

# Persist the PostgreSQL credentials for scripts/validate.sh, matching the contract of scripts/deploy.sh, and the
# other deployment secrets for the next run of this script
cat >"$STATE_FILE" <<EOF
POSTGRES_ADMIN_PASSWORD=$POSTGRES_ADMIN_PASSWORD
POSTGRES_HOST=$POSTGRES_HOST
POSTGRES_PORT=$POSTGRES_PORT
SIGN_KEY=$SIGN_KEY
INTERNAL_TOKEN=$INTERNAL_TOKEN
EOF

# Create the zip package of the web app
cd "$CURRENT_DIR/../src" || exit
if [ -f "$WEBAPP_ZIPFILE" ]; then
	rm "$WEBAPP_ZIPFILE"
fi
echo "Creating zip package of the web app..."
zip -r "$WEBAPP_ZIPFILE" app.py gunicorn.conf.py requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$WEBAPP_ZIPFILE]..."
# On Azure the deployment service can answer 504 Gateway Timeout while it warms up, or DeploymentInProgress while
# the build of the previous deployment still runs: the upload is tried again. The startup of the site isn't
# tracked: the tracking counted a failed start of the container that ran before the code was deployed, and
# reported a running site as failed after ten minutes; what calls the web app afterwards waits for it instead.
WEBAPP_DEPLOY_RETRY_COUNT="${WEBAPP_DEPLOY_RETRY_COUNT:-10}"
WEBAPP_DEPLOY_RETRY_SLEEP="${WEBAPP_DEPLOY_RETRY_SLEEP:-30}"
WEBAPP_DEPLOYED=0
for ATTEMPT in $(seq 1 "$WEBAPP_DEPLOY_RETRY_COUNT"); do
	if az webapp deploy \
		--resource-group $RESOURCE_GROUP_NAME \
		--name "$WEB_APP_NAME" \
		--src-path "$WEBAPP_ZIPFILE" \
		--type zip \
		--async true \
		--track-status false 1>/dev/null; then
		WEBAPP_DEPLOYED=1
		break
	fi
	if [ "$ATTEMPT" -lt "$WEBAPP_DEPLOY_RETRY_COUNT" ]; then
		echo "Attempt $ATTEMPT of $WEBAPP_DEPLOY_RETRY_COUNT to deploy web app [$WEB_APP_NAME] failed. Waiting [$WEBAPP_DEPLOY_RETRY_SLEEP] seconds before retry..."
		sleep "$WEBAPP_DEPLOY_RETRY_SLEEP"
	fi
done

if [ $WEBAPP_DEPLOYED -eq 1 ]; then
	echo "Web app [$WEB_APP_NAME] deployed successfully"
else
	echo "Failed to deploy web app [$WEB_APP_NAME]"
	exit 1
fi
rm -f "$WEBAPP_ZIPFILE"

# Create the zip package of the function app
cd "$CURRENT_DIR/../function" || exit
if [ -f "$WORKER_ZIPFILE" ]; then
	rm "$WORKER_ZIPFILE"
fi
echo "Creating zip package of the function app..."
zip -r "$WORKER_ZIPFILE" function_app.py host.json requirements.txt

# Deploy the function app
echo "Deploying function app [$FUNCTION_APP_NAME] with zip file [$WORKER_ZIPFILE]..."
# On Azure the first deployment to a new function app can time out (504) while its deployment site starts, so a failed
# attempt is retried
DEPLOYED=0
for ((ATTEMPT = 1; ATTEMPT <= DEPLOY_RETRY_COUNT; ATTEMPT++)); do
	az functionapp deploy \
		--resource-group $RESOURCE_GROUP_NAME \
		--name "$FUNCTION_APP_NAME" \
		--src-path "$WORKER_ZIPFILE" \
		--type zip \
		--async true 1>/dev/null

	if [[ $? == 0 ]]; then
		DEPLOYED=1
		break
	fi

	if [[ $ATTEMPT -lt $DEPLOY_RETRY_COUNT ]]; then
		echo "Attempt $ATTEMPT of $DEPLOY_RETRY_COUNT to deploy function app [$FUNCTION_APP_NAME] failed. Waiting [$DEPLOY_RETRY_SLEEP] seconds before retry..."
		sleep $DEPLOY_RETRY_SLEEP
	fi
done

if [[ $DEPLOYED == 1 ]]; then
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully"
else
	echo "Failed to deploy function app [$FUNCTION_APP_NAME]"
	exit 1
fi
rm -f "$WORKER_ZIPFILE"

echo "Deployment completed. Web app available at: http://$WEB_APP_HOSTNAME"
