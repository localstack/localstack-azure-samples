# Azure CLI Deployment

This directory includes Bash scripts designed for deploying and testing the sample Web App utilizing the `azlocal` CLI. For further details about the sample application, refer to the [Azure Web App with Azure CosmosDB for NoSQL API](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://azure.localstack.cloud/): Local Azure cloud emulator for development and testing
- [Visual Studio Code](https://code.visualstudio.com/): Code editor installed on one of the [supported platforms](https://code.visualstudio.com/docs/supporting/requirements#_platforms)
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [Azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [Python](https://www.python.org/downloads/): Python runtime (version 3.12 or above)
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The deployment script uses the `azlocal` CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Deployment Script 

You can use the `deploy.sh` script to automate the deployment of all Azure resources and the sample application in a single step, streamlining setup and reducing manual configuration.

```bash
#!/bin/bash


PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
APP_SERVICE_PLAN_SKU="S1"
WEB_APP_NAME="${PREFIX}-webapp-nosql-${SUFFIX}"
COSMOSDB_ACCOUNT_NAME="${PREFIX}-nosqlapi-${SUFFIX}"
ZIPFILE="${WEB_APP_NAME}.zip"

RANDOM_SUFFIX=$(echo $RANDOM)
NEW_DB_NAME="vacationplanner_${RANDOM_SUFFIX}"
AZURECOSMOSDB_DATABASENAME=$NEW_DB_NAME
AZURECOSMOSDB_CONTAINERNAME="activities_${RANDOM_SUFFIX}"

# Start azure CLI local mode session
azlocal login

# Change the current directory to the script's directory
#cd "$CURRENT_DIR" || exit

# Validates if the resource group exists in the subscription, if not creates it
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists..."
azlocal group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists"
	echo "Creating resource group [$RESOURCE_GROUP_NAME]..."

	# Create the resource group
    azlocal group create \
        --name $RESOURCE_GROUP_NAME \
        --location $LOCATION \
        --only-show-errors 1> /dev/null \

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created."
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME]."
		exit
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists."
fi

echo "Create CosmosDB NoSQL Account"
    export AZURECOSMOSDB_ENDPOINT=$(azlocal cosmosdb create \
        --resource-group $RESOURCE_GROUP_NAME \
        --name $WEB_APP_NAME \
        --locations regionName=$LOCATION \
        --query "documentEndpoint" \
        --output tsv)

echo "Account created"
echo "AZURECOSMOSDB_ENDPOINT set to $AZURECOSMOSDB_ENDPOINT"

echo "Fetching DB Account primary master key"
export AZURECOSMOSDB_PRIMARY_KEY=$(azlocal cosmosdb keys list \
        --resource-group $RESOURCE_GROUP_NAME \
        --name $WEB_APP_NAME \
        --query "primaryMasterKey" \
        --output tsv)
echo "Primary master key is $AZURECOSMOSDB_PRIMARY_KEY"

echo "Creating App service"
azlocal appservice plan create --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP_NAME --sku B1 --is-linux
echo "App service created"

echo "Creating Web App"
azlocal webapp create --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP_NAME --plan $WEB_APP_NAME --runtime PYTHON:3.13
echo "Web App created"

echo "Configure appsettings environment variables"
azlocal webapp config appsettings set \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $WEB_APP_NAME \
    --settings AZURECOSMOSDB_ENDPOINT=$AZURECOSMOSDB_ENDPOINT \
               AZURECOSMOSDB_DATABASENAME=$AZURECOSMOSDB_DATABASENAME \
               AZURECOSMOSDB_CONTAINERNAME=$AZURECOSMOSDB_CONTAINERNAME \
               AZURECOSMOSDB_PRIMARY_KEY=$AZURECOSMOSDB_PRIMARY_KEY

# Print the application settings of the web app
echo "Retrieving application settings for web app [$WEB_APP_NAME]..."
azlocal webapp config appsettings list \
	--resource-group $RESOURCE_GROUP_NAME \
	--name $WEB_APP_NAME

# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py cosmosdb_client.py static templates requirements.txt

# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
echo "Using azlocal webapp deploy command for LocalStack emulator environment."
azlocal webapp deploy \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $WEB_APP_NAME \
    --src-path ${ZIPFILE} \
    --type zip \
    --async true \
    --debug \
    --verbose 1>/dev/null

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi
```

> [!NOTE]
> You can use the `azlocal` CLI as a drop-in replacement for the `az` CLI to direct all commands to the LocalStack for Azure emulator. Alternatively, run `azlocal start_interception` to automatically intercept and redirect all `az` commands to LocalStack. To revert back to the default behavior and send commands to the Azure cloud, run `azlocal stop_interception`.

## Deployment

You can set up the Azure emulator by utilizing LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/?__hstc=108988063.8aad2b1a7229945859f4d9b9bb71e05d.1743148429561.1758793541854.1758810151462.32&__hssc=108988063.3.1758810151462&__hsfp=3945774529) to obtain your Auth Token and specify it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure-alpha). To pull the Azure Docker image, execute the following command:

```bash
docker pull localstack/localstack-azure-alpha
```

Start the LocalStack Azure emulator using the localstack CLI, execute the following command:

```bash
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>
IMAGE_NAME=localstack/localstack-azure-alpha localstack start
```

Navigate to the `scripts` folder:

```bash
cd samples/web-app-cosmosdb-nosql-api/python/scripts
```

Make the script executable:

```bash
chmod +x deploy.sh
```

Run the deployment script:

```bash
./deploy.sh
```

## Validation

After deployment, you can use the `validate.sh` script to verify that all resources were created and configured correctly:

```bash
#!/bin/bash

# Variables
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	AZ="azlocal"
else
	echo "Using standard az for AzureCloud environment."
	AZ="az"
fi

# Check resource group
$AZ group show \
--name local-rg \
--output table

# List resources
$AZ resource list \
--resource-group local-rg \
--output table

# Check Azure Web App
$AZ webapp show \
--name local-webapp-nosql-test \
--resource-group local-rg \
--output table

# Check Azure CosmosDB account
$AZ cosmosdb show \
--name local-webapp-nosql-test \
--resource-group local-rg \
--output table
```

## Cleanup

To destroy all created resources:

```bash
# Delete resource group and all contained resources
az group delete --name local-rg --yes --no-wait

# Verify deletion
az group list --output table
```

This will remove all Azure resources created by the CLI deployment script.

## Related Documentation

- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [LocalStack for Azure Documentation](https://azure.localstack.cloud/)