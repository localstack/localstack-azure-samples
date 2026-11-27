#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
RESOURCE_GROUP_NAME="$PREFIX-rg"
LOCATION="westeurope"
VALIDATE_TEMPLATE=1
USE_WHAT_IF=0
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="webapp_app.zip"
MANAGED_IDENTITY_TYPE="UserAssigned" # SystemAssigned or UserAssigned

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Validates if the resource group exists in the subscription, if not creates it
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	# Create the resource group
	az group create \
		--name $RESOURCE_GROUP_NAME \
		--location $LOCATION \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created in the subscription [$SUBSCRIPTION_NAME]"
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]"
		exit 1
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists in the subscription [$SUBSCRIPTION_NAME]"
fi

# Validates the Bicep template
if [[ $VALIDATE_TEMPLATE == 1 ]]; then
	if [[ $USE_WHAT_IF == 1 ]]; then
		# Execute a deployment What-If operation at resource group scope.
		echo "Previewing changes deployed by Bicep template [$TEMPLATE]..."
		az deployment group what-if \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $TEMPLATE \
			--parameters $PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			managedIdentityType=$MANAGED_IDENTITY_TYPE \
			--only-show-errors

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			exit 1
		fi
	else
		# Validate the Bicep template
		echo "Validating Bicep template [$TEMPLATE]..."
		output=$(az deployment group validate \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $TEMPLATE \
			--parameters $PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			managedIdentityType=$MANAGED_IDENTITY_TYPE \
			--only-show-errors)

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			echo "$output"
			exit 1
		fi
	fi
fi

# Deploy the Bicep template
echo "Deploying Bicep template [$TEMPLATE]..."
if DEPLOYMENT_OUTPUTS=$(az deployment group create \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors \
	--template-file $TEMPLATE \
	--parameters $PARAMETERS \
	--parameters location=$LOCATION \
	prefix=$PREFIX \
	suffix=$SUFFIX \
	managedIdentityType=$MANAGED_IDENTITY_TYPE \
	--query 'properties.outputs' -o json); then
	echo "Bicep template [$TEMPLATE] deployed successfully. Outputs:"
	echo "$DEPLOYMENT_OUTPUTS" | jq .
	APP_SERVICE_PLAN_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.appServicePlanName.value')
	WEB_APP_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.webAppName.value')
	WEB_APP_URL=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.webAppUrl.value')
	STORAGE_ACCOUNT_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.storageAccountName.value')
	CONTAINER_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.storageContainerName.value')
	echo "Deployment details:"
	echo "- appServicePlanName: $APP_SERVICE_PLAN_NAME"
	echo "- webAppName: $WEB_APP_NAME"
	echo "- webAppUrl: $WEB_APP_URL"
	echo "- storageAccountName: $STORAGE_ACCOUNT_NAME"
	echo "- storageContainerName: $CONTAINER_NAME"
else
	echo "Failed to deploy Bicep template [$TEMPLATE]"
	exit 1
fi

# The key of the storage account, which uploads the sample activities as the Azure CLI scripts do
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
	--account-name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[0].value" \
	--output tsv \
	--only-show-errors)

if [[ -z $STORAGE_ACCOUNT_KEY ]]; then
	echo "Failed to retrieve the key of the [$STORAGE_ACCOUNT_NAME] storage account."
	exit 1
fi

# Seed the container with sample activities, one blob per activity, as the other samples seed their databases. Every
# blob has a fixed name, so a second run finds the ones already there and uploads only the missing ones.
SAMPLE_ACTIVITIES=(
	"pisa|Visit the Leaning Tower in Pisa"
	"volterra|Explore Etruscan walls in Volterra"
	"san-gimignano|Climb Torre Grossa in San Gimignano"
	"siena|Walk across Piazza del Campo in Siena"
	"montalcino|Taste Brunello wine in Montalcino"
	"pienza|Sample Pecorino cheese in Pienza"
	"florence|Admire Michelangelo's David in Florence"
	"viareggio-beach|Relax by the beach in Viareggio"
	"viareggio-promenade|Stroll along the Viareggio promenade"
)
echo "Seeding the [$CONTAINER_NAME] container of the [$STORAGE_ACCOUNT_NAME] storage account with sample activities..."
for SAMPLE_ACTIVITY in "${SAMPLE_ACTIVITIES[@]}"; do
	SAMPLE_BLOB_NAME="sample-${SAMPLE_ACTIVITY%%|*}-activity.txt"
	SAMPLE_BLOB_EXISTS=$(az storage blob exists \
		--account-name "$STORAGE_ACCOUNT_NAME" \
		--account-key "$STORAGE_ACCOUNT_KEY" \
		--container-name "$CONTAINER_NAME" \
		--name "$SAMPLE_BLOB_NAME" \
		--query exists \
		--output tsv \
		--only-show-errors)

	if [[ $SAMPLE_BLOB_EXISTS == "true" ]]; then
		echo "Sample activity [$SAMPLE_BLOB_NAME] already exists in the [$CONTAINER_NAME] container."
		continue
	fi

	az storage blob upload \
		--account-name "$STORAGE_ACCOUNT_NAME" \
		--account-key "$STORAGE_ACCOUNT_KEY" \
		--container-name "$CONTAINER_NAME" \
		--name "$SAMPLE_BLOB_NAME" \
		--data "${SAMPLE_ACTIVITY#*|}" \
		--content-type "text/plain" \
		--no-progress \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "Sample activity [$SAMPLE_BLOB_NAME] uploaded to the [$CONTAINER_NAME] container."
	else
		echo "Failed to upload sample activity [$SAMPLE_BLOB_NAME] to the [$CONTAINER_NAME] container."
		exit 1
	fi
done

# Validation before deploying the web app
if [[ -z "$WEB_APP_NAME" ]]; then
	echo "Web App Name is empty. Exiting."
	exit 1
fi

# CD into the web app directory
cd ../src || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" . -x "bin/*" "obj/*" "publish/*" "*.zip"

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
# On Azure the deployment service can answer 504 Gateway Timeout while it warms up, or DeploymentInProgress while
# the build of the previous deployment still runs: the upload is tried again. The startup of the site isn't
# tracked: the tracking counted a failed start of the container that ran before the code was deployed, and
# reported a running site as failed after ten minutes; what calls the web app afterwards waits for it instead.
WEBAPP_DEPLOY_RETRY_COUNT="${WEBAPP_DEPLOY_RETRY_COUNT:-10}"
WEBAPP_DEPLOY_RETRY_SLEEP="${WEBAPP_DEPLOY_RETRY_SLEEP:-30}"
WEBAPP_DEPLOYED=0
for ATTEMPT in $(seq 1 "$WEBAPP_DEPLOY_RETRY_COUNT"); do
	if az webapp deploy \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$WEB_APP_NAME" \
		--src-path "$ZIPFILE" \
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
	echo "Web app [$WEB_APP_NAME] deployed successfully."
else
	echo "Failed to deploy web app [$WEB_APP_NAME]."
	exit 1
fi

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi
