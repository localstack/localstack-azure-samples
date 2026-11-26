#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
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

# Intialize Terraform
echo "Initializing Terraform..."
terraform init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
        -var "prefix=$PREFIX" \
        -var "suffix=$SUFFIX" \
        -var "location=$LOCATION"

if [[ $? != 0 ]]; then
        echo "Terraform plan failed. Exiting."
        exit 1
fi

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
terraform apply -auto-approve tfplan

if [[ $? != 0 ]]; then
        echo "Terraform apply failed. Exiting."
        exit 1
fi

# Get the output values
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
WEB_APP_NAME=$(terraform output -raw web_app_name)
ACCOUNT_NAME=$(terraform output -raw cosmosdb_account_name)

if [[ -z "$RESOURCE_GROUP_NAME" || -z "$WEB_APP_NAME" || -z "$ACCOUNT_NAME" ]]; then
	echo "Resource Group Name, Web App Name, or Cosmos DB Account Name is empty. Exiting."
	exit 1
fi

# Print the names of the application settings of the web app, never their values, which hold secrets
echo "Retrieving the names of the application settings of the web app [$WEB_APP_NAME]..."
az webapp config appsettings list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--query "[].name" \
	--output tsv

# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py mongodb.py gunicorn.conf.py static templates requirements.txt

# Deploy the web app
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

# Print the list of resources in the resource group
echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table 