#!/bin/bash

# Variables
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Start azure CLI local mode session
# azlocal start_interception

# Delete any existing terraform state and plan files
rm -f terraform.tfstate terraform.tfstate.backup tfplan

# Run terraform init and apply
echo "Initializing Terraform..."
tflocal init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
tflocal plan -out=tfplan

if [[ $? != 0 ]]; then
		echo "Terraform plan failed. Exiting."
		exit 1
fi

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
tflocal apply -auto-approve tfplan

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
zip -r "$ZIPFILE" app.py cosmosdb.py static templates requirements.txt

# Deploy the web app
azlocal webapp deploy \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$WEB_APP_NAME" \
  --src-path planner_website.zip \
  --type zip \
  --async true

# Remove the zip package of the web app
rm "$ZIPFILE"
