#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Start azure CLI local mode session
# azlocal start_interception

# Run terraform init and apply
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using tflocal for LocalStack emulator environment."
	TERRAFORM_CMD="tflocal"
else
	echo "Using standard terraform for AzureCloud environment."
	TERRAFORM_CMD="terraform"
fi

echo "Initializing Terraform..."
$TERRAFORM_CMD init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
$TERRAFORM_CMD plan -out=tfplan \
	-var="prefix=$PREFIX" \
	-var="suffix=$SUFFIX" \
	-var="location=$LOCATION"

if [[ $? != 0 ]]; then
		echo "Terraform plan failed. Exiting."
		exit 1
fi

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
$TERRAFORM_CMD apply -auto-approve tfplan

if [[ $? != 0 ]]; then
		echo "Terraform apply failed. Exiting."
		exit 1
fi

# Get the output values
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
WEB_APP_NAME=$(terraform output -raw web_app_name)

# Print the variables
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Web App: $WEB_APP_NAME"

# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py mongodb.py static templates requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal webapp deploy command for LocalStack emulator environment."
	azlocal webapp deploy \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$WEB_APP_NAME" \
		--src-path "$ZIPFILE" \
		--type zip \
		--async true 1>/dev/null
else
	echo "Using standard az webapp deploy command for AzureCloud environment."
	az webapp deploy \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$WEB_APP_NAME" \
		--src-path "$ZIPFILE" \
		--type zip \
		--async true 1>/dev/null
fi

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi