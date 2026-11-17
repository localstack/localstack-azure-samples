#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEBAPP_ZIPFILE="linklet_webapp.zip"
WORKER_ZIPFILE="linklet_worker.zip"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Resolve the object id of the deploying principal. azurerm_key_vault_secret writes through the Key Vault
# data plane, so on Azure the principal running terraform apply needs Key Vault Secrets Officer on the
# vault; the configuration assigns it when the id is known. The lookup goes through Microsoft Graph; when
# it fails the assignment is skipped and the role becomes a prerequisite (see the README).
ACCOUNT_USER_TYPE=$(az account show --query user.type --output tsv --only-show-errors)
ACCOUNT_USER_NAME=$(az account show --query user.name --output tsv --only-show-errors)

if [[ $ACCOUNT_USER_TYPE == "user" ]]; then
	DEPLOYER_PRINCIPAL_TYPE="User"
	DEPLOYER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv --only-show-errors 2>/dev/null)
else
	DEPLOYER_PRINCIPAL_TYPE="ServicePrincipal"
	DEPLOYER_OBJECT_ID=$(az ad sp show --id "$ACCOUNT_USER_NAME" --query id --output tsv --only-show-errors 2>/dev/null)
fi

# Microsoft Graph lookups need directory permissions a pipeline principal often lacks. Fall back to the oid
# claim of the CLI's own access token, which identifies the same principal without any Graph call.
if [[ -z $DEPLOYER_OBJECT_ID ]]; then
	DEPLOYER_OBJECT_ID=$(az account get-access-token --query accessToken --output tsv --only-show-errors 2>/dev/null |
		cut -d. -f2 | tr '_-' '/+' | awk '{ pad = length($0) % 4; if (pad == 2) $0 = $0 "=="; else if (pad == 3) $0 = $0 "="; print }' |
		base64 -d 2>/dev/null | jq -r '.oid // empty' 2>/dev/null)
fi

if [[ -n $DEPLOYER_OBJECT_ID ]]; then
	echo "Deploying principal [$ACCOUNT_USER_NAME] ($DEPLOYER_PRINCIPAL_TYPE) has object id [$DEPLOYER_OBJECT_ID]"
else
	echo "WARNING: could not resolve the object id of the deploying principal [$ACCOUNT_USER_NAME]; the Key Vault Secrets Officer role on the key vault must already be assigned to it"
	DEPLOYER_OBJECT_ID=""
fi

# Initialize Terraform
echo "Initializing Terraform..."
terraform init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "deployer_object_id=$DEPLOYER_OBJECT_ID" \
	-var "deployer_principal_type=$DEPLOYER_PRINCIPAL_TYPE"

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
STORAGE_ACCOUNT_NAME=$(terraform output -raw storage_account_name)
LOG_ANALYTICS_NAME=$(terraform output -raw log_analytics_workspace_name)
WEB_APP_NAME=$(terraform output -raw web_app_name)
FUNCTION_APP_NAME=$(terraform output -raw function_app_name)

# Check if output values are empty
if [[ -z "$WEB_APP_NAME" || -z "$FUNCTION_APP_NAME" ]]; then
	echo "Web App Name or Function App Name is empty. Exiting."
	exit 1
fi

# Persist the PostgreSQL credentials for scripts/validate.sh, matching the
# contract of scripts/deploy.sh.
cat >"$CURRENT_DIR/../scripts/.last_deploy.${PREFIX}.env" <<EOF
POSTGRES_ADMIN_PASSWORD=$(terraform output -raw postgres_password)
POSTGRES_HOST=$(terraform output -raw postgres_host)
POSTGRES_PORT=$(terraform output -raw postgres_port)
EOF

# Change current directory to the web app source folder
cd "$CURRENT_DIR/../src" || exit

# Remove any existing zip package of the web app
if [ -f "$WEBAPP_ZIPFILE" ]; then
	rm "$WEBAPP_ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$WEBAPP_ZIPFILE" app.py gunicorn.conf.py requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$WEBAPP_ZIPFILE]..."
az webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$WEBAPP_ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app [$WEB_APP_NAME] deployed successfully."
else
	echo "Failed to deploy web app [$WEB_APP_NAME]."
	exit 1
fi

# Remove the zip package of the web app
if [ -f "$WEBAPP_ZIPFILE" ]; then
	rm "$WEBAPP_ZIPFILE"
fi

# Change current directory to the function folder
cd "$CURRENT_DIR/../function" || exit

# Remove any existing zip package of the function app
if [ -f "$WORKER_ZIPFILE" ]; then
	rm "$WORKER_ZIPFILE"
fi

# Create the zip package of the function app
echo "Creating zip package of the function app..."
zip -r "$WORKER_ZIPFILE" function_app.py host.json requirements.txt

# Deploy the function app
echo "Deploying function app [$FUNCTION_APP_NAME] with zip file [$WORKER_ZIPFILE]..."
az functionapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FUNCTION_APP_NAME" \
	--src-path "$WORKER_ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully."
else
	echo "Failed to deploy function app [$FUNCTION_APP_NAME]."
	exit 1
fi

# Remove the zip package of the function app
if [ -f "$WORKER_ZIPFILE" ]; then
	rm "$WORKER_ZIPFILE"
fi

WEB_APP_HOST=$(cd "$CURRENT_DIR" && terraform output -raw web_app_host)
echo "Deployment completed. Web app available at: http://$WEB_APP_HOST"
