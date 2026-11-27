#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
MANAGED_IDENTITY_TYPE='UserAssigned' # SystemAssigned or UserAssigned
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Dual-target provider configuration. providers.tf hardcodes nothing: the azurerm provider reads its endpoints and the
# target subscription from the ARM_* environment variables exported here.
# - On both targets: the subscription and tenant of the active az account.
# - Only when the active az cloud is LocalStack: the emulator's metadata endpoint, taken from the az cloud registration
#   that `lstk az start-interception` created, so nothing is hardcoded here either.
ACTIVE_CLOUD=$(az cloud show --query name --output tsv --only-show-errors)
ARM_SUBSCRIPTION_ID=$(az account show --query id --output tsv --only-show-errors)
ARM_TENANT_ID=$(az account show --query tenantId --output tsv --only-show-errors)
export ARM_SUBSCRIPTION_ID ARM_TENANT_ID

if [[ $ACTIVE_CLOUD == "LocalStack" ]]; then
	RESOURCE_MANAGER_ENDPOINT=$(az cloud show --query endpoints.resourceManager --output tsv --only-show-errors)
	METADATA_HOSTNAME="${RESOURCE_MANAGER_ENDPOINT#https://}"
	export ARM_METADATA_HOSTNAME="${METADATA_HOSTNAME%/}"
	echo "Active cloud is [$ACTIVE_CLOUD]: Terraform targets the emulator at [$RESOURCE_MANAGER_ENDPOINT]"
else
	# Cleared rather than merely not set: a value inherited from an earlier emulator deployment in the same shell would
	# keep the provider doing metadata discovery against the emulator while the CLI is on Azure.
	unset ARM_METADATA_HOSTNAME
	echo "Active cloud is [$ACTIVE_CLOUD]: Terraform targets Azure subscription [$ARM_SUBSCRIPTION_ID]"
fi

echo "Initializing Terraform..."
terraform init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "managed_identity_type=$MANAGED_IDENTITY_TYPE"

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
terraform apply -auto-approve tfplan

if [[ $? != 0 ]]; then
	echo "Terraform apply failed. Exiting."
	exit 1
fi

# Get the output values
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
STORAGE_ACCOUNT_NAME=$(terraform output -raw storage_account_name)
CONTAINER_NAME=$(terraform output -raw storage_container_name)
WEB_APP_NAME=$(terraform output -raw web_app_name)

# Check if output values are empty
if [[ -z "$WEB_APP_NAME" || -z "$STORAGE_ACCOUNT_NAME" ]]; then
	echo "Web App Name or Storage Account Name is empty. Exiting."
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

# Change current directory to source folder
cd "../src" || exit

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
