#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}" #system or user
SUFFIX="${SUFFIX:-test}"
LOCATION='westeurope'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="function_app.zip"
DEPLOY_RETRY_COUNT=3
DEPLOY_RETRY_SLEEP=30

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

echo "Initializing Terraform..."
terraform init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION"

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
terraform apply -auto-approve tfplan

if [[ $? != 0 ]]; then
	echo "Terraform apply failed. Exiting."
	exit 1
fi

# Get the output values
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
FUNCTION_APP_NAME=$(terraform output -raw function_app_name)

# Print the variables
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Function App: $FUNCTION_APP_NAME"

# CD into the function app directory
cd ../src || exit

# Create the zip package of the function app: the remote build installs requirements.txt
rm -f $ZIPFILE
zip -r $ZIPFILE function_app.py host.json requirements.txt

# Deploy the function app using the zip file
echo "Deploying function app [$FUNCTION_APP_NAME]..."
# On Azure the first deployment to a new function app can time out (504) while its deployment site starts, so a failed
# attempt is retried
DEPLOYED=0
for ((ATTEMPT = 1; ATTEMPT <= DEPLOY_RETRY_COUNT; ATTEMPT++)); do
	az functionapp deploy \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$FUNCTION_APP_NAME" \
		--src-path "$ZIPFILE" \
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
	echo "Function app [$FUNCTION_APP_NAME] deployed successfully."
else
	echo "Failed to deploy function app [$FUNCTION_APP_NAME]."
	exit 1
fi
