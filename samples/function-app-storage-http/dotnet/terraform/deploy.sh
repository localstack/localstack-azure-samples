#!/bin/bash

# Variables
PREFIX='user' #system or user
SUFFIX='test'
LOCATION='westeurope'
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="function_app.zip"

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

	# Log Azure auth environment variables before unsetting
	echo "[DEBUG] Azure auth env vars before unsetting:"
	echo "[DEBUG]   ARM_CLIENT_ID=${ARM_CLIENT_ID:-<not set>}"
	echo "[DEBUG]   ARM_CLIENT_SECRET=${ARM_CLIENT_SECRET:+<set but hidden>}${ARM_CLIENT_SECRET:-<not set>}"
	echo "[DEBUG]   ARM_TENANT_ID=${ARM_TENANT_ID:-<not set>}"
	echo "[DEBUG]   ARM_SUBSCRIPTION_ID=${ARM_SUBSCRIPTION_ID:-<not set>}"
	echo "[DEBUG]   AZURE_CLIENT_ID=${AZURE_CLIENT_ID:-<not set>}"
	echo "[DEBUG]   AZURE_TENANT_ID=${AZURE_TENANT_ID:-<not set>}"

	# Unset Azure auth environment variables to prevent interference from CI secrets
	unset ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_TENANT_ID ARM_SUBSCRIPTION_ID
	unset AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID

	echo "[DEBUG] Azure auth env vars after unsetting: all cleared"
	AZ="azlocal"
else
	echo "Using standard terraform and az for AzureCloud environment."
	TERRAFORM="terraform"
	AZ="az"
fi

echo "[DEBUG] Cloud name: '$CLOUD_NAME', Environment: '$ENVIRONMENT', Tools: TERRAFORM=$TERRAFORM, AZ=$AZ"
echo "[DEBUG] TERRAFORM command location: $(which $TERRAFORM 2>/dev/null || echo 'not found')"

echo "Initializing Terraform..."
$TERRAFORM init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
$TERRAFORM plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION"

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
FUNCTION_APP_NAME=$($TERRAFORM output -raw function_app_name)

# Print the variables
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Function App: $FUNCTION_APP_NAME"

# CD into the function app directory
cd ../src/sample || exit

# Clean and build the project in Release configuration
dotnet clean
dotnet build -c Release

# Publish the project to a publish directory
dotnet publish -c Release -o publish

# Create deployment zip from the published output
cd publish || exit
zip -r ../$ZIPFILE .
cd .. || exit

# Deploy the function app using the zip file
echo "Deploying function app [$FUNCTION_APP_NAME]..."
$AZ functionapp deploy \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$FUNCTION_APP_NAME" \
    --src-path $ZIPFILE \
    --type zip 1> /dev/null
