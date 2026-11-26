#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX='test'
LOCATION='westeurope'
SERVICEBUS_QUEUE_NAME="myqueue" # Queue name is hardcoded in the application properties
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
        -var "location=$LOCATION" \
				-var "queue_name=$SERVICEBUS_QUEUE_NAME"

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
SERVICEBUS_NAMESPACE_NAME=$(terraform output -raw namespace_name)


if [[ -z "$SERVICEBUS_NAMESPACE_NAME" ]]; then
	echo "Service Bus Namespace Name is empty. Exiting."
	exit 1
fi

# Retrieve the connection string for the Service Bus namespace
echo "Retrieving connection string for [$SERVICEBUS_NAMESPACE_NAME] Service Bus namespace..."
AZURE_SERVICEBUS_CONNECTION_STRING=$(az servicebus namespace authorization-rule keys list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--namespace-name "$SERVICEBUS_NAMESPACE_NAME" \
	--name RootManageSharedAccessKey \
	--query primaryConnectionString \
	--output tsv)

if [[ $? -eq 0 ]] && [[ -n "$AZURE_SERVICEBUS_CONNECTION_STRING" ]]; then
	export AZURE_SERVICEBUS_CONNECTION_STRING
	echo "Connection string retrieved successfully."
else
	echo "Failed to retrieve connection string."
	exit 1
fi

# Start the Java application. Maven's mvn launcher is a shell script that hands its own paths to Java,
# a Windows program on Windows, and relies on Git Bash and MSYS2 converting them, so it runs with that
# conversion back on even when MSYS_NO_PATHCONV is set, as the README asks.
echo "Starting Java application..."
cd "$CURRENT_DIR/../app" && (unset MSYS_NO_PATHCONV; mvn clean spring-boot:run)

