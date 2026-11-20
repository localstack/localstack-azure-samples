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
cd ../src/sample || exit

# Clean and build the project in Release configuration
dotnet clean
dotnet build -c Release

# Publish the project to a publish directory
dotnet publish -c Release -o publish || exit 1

# Create deployment zip from the published output
rm -f $ZIPFILE
cd publish || exit
zip -r ../$ZIPFILE .
cd .. || exit

# Deploy the function app using the zip file
echo "Deploying function app [$FUNCTION_APP_NAME]..."
# The package is already built. az functionapp deploy got an Oryx build of it on Azure although the app settings set
# SCM_DO_BUILD_DURING_DEPLOYMENT to false, and that build fails on a published .NET app. On Linux,
# az functionapp deployment source config-zip sets the setting to false and waits until the deployment site sees it
# before it deploys. On Azure the first deployment to a new function app can also time out (504) while its deployment
# site starts, so a failed attempt is retried
DEPLOYED=0
for ((ATTEMPT = 1; ATTEMPT <= DEPLOY_RETRY_COUNT; ATTEMPT++)); do
	az functionapp deployment source config-zip \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$FUNCTION_APP_NAME" \
		--src "$ZIPFILE" \
		--only-show-errors 1>/dev/null

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
