#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEBAPP_ZIPFILE="linklet_webapp.zip"
WORKER_ZIPFILE="linklet_worker.zip"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Initialize Terraform
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
cat >"$CURRENT_DIR/../scripts/.last_deploy.env" <<EOF
POSTGRES_ADMIN_PASSWORD=$(terraform output -raw postgres_password)
POSTGRES_HOST=$(terraform output -raw postgres_host)
POSTGRES_PORT=$(terraform output -raw postgres_port)
EOF

# Attach diagnostic settings for the storage account to the Log Analytics workspace
echo "Attaching diagnostic settings for [$STORAGE_ACCOUNT_NAME] to [$LOG_ANALYTICS_NAME]..."
STORAGE_ACCOUNT_ID=$(az storage account show \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv)
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query id \
	--output tsv)
az monitor diagnostic-settings create \
	--name default \
	--resource "$STORAGE_ACCOUNT_ID" \
	--workspace "$LOG_ANALYTICS_ID" \
	--metrics '[{"category":"Transaction","enabled":true}]' \
	--output none

if [ $? -eq 0 ]; then
	echo "Diagnostic settings successfully attached."
else
	# Best-effort: validate.sh step 8 fails the run if diagnostics are missing.
	echo "Failed to attach diagnostic settings."
fi

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
