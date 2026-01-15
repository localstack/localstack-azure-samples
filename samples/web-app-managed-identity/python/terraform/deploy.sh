#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
MANAGED_IDENTITY_TYPE='SystemAssigned' # SystemAssigned or UserAssigned
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Determine environment
if command -v az >/dev/null 2>&1; then
	CLOUD_NAME=$(az cloud show --query name --output tsv 2>&1 || echo "")

	if [[ "$CLOUD_NAME" == "LocalStack" ]]; then
		ENVIRONMENT="LocalStack"
	elif [[ "$CLOUD_NAME" == "AzureCloud" ]]; then
		ENVIRONMENT="AzureCloud"
	else
		ENVIRONMENT="AzureCloud"
	fi
else
	ENVIRONMENT="AzureCloud"
fi

# Run terraform init and apply
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using tflocal and azlocal for LocalStack emulator environment."
	TERRAFORM="tflocal"
	AZ="azlocal"
else
	echo "Using standard terraform and az for AzureCloud environment."
	TERRAFORM="terraform"
	AZ="az"
fi

echo "[DEBUG] Cloud name: '$CLOUD_NAME', Environment: '$ENVIRONMENT', Tools: TERRAFORM=$TERRAFORM, AZ=$AZ"

echo "Initializing Terraform..."
$TERRAFORM init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
$TERRAFORM plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "managed_identity_type=$MANAGED_IDENTITY_TYPE"

if [[ $? != 0 ]]; then
	echo "Terraform plan failed. Exiting."
	exit 1
fi

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
$TERRAFORM apply -auto-approve tfplan

if [[ $? != 0 ]]; then
	echo "Terraform apply failed. Exiting."
	exit 1
fi

# Get the output values
RESOURCE_GROUP_NAME=$($TERRAFORM output -raw resource_group_name)
STORAGE_ACCOUNT_NAME=$($TERRAFORM output -raw storage_account_name)
WEB_APP_NAME=$($TERRAFORM output -raw web_app_name)

# Check if output values are empty
if [[ -z "$WEB_APP_NAME" || -z "$STORAGE_ACCOUNT_NAME" ]]; then
	echo "Web App Name or Storage Account Name is empty. Exiting."
	exit 1
fi

# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py activities.py database.py static templates requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
$AZ webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

if [ $? -eq 0 ]; then
	echo "Web app [$WEB_APP_NAME] created successfully."
else
	echo "Failed to create web app [$WEB_APP_NAME]."
	exit 1
fi

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi
