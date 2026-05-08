#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
ACR_TEMPLATE="acr.bicep"
ACR_PARAMETERS="acr.bicepparam"
MAIN_TEMPLATE="main.bicep"
MAIN_PARAMETERS="main.bicepparam"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOCATION="westeurope"
IMAGE_NAME="custom-image-webapp"
IMAGE_TAG="v1"
LOCAL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
VALIDATE_TEMPLATE=1
USE_WHAT_IF=0
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Validates if the resource group exists in the subscription, if not creates it
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
az group show --name $RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	# Create the resource group
	az group create \
		--name $RESOURCE_GROUP_NAME \
		--location $LOCATION \
		--only-show-errors 1> /dev/null

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created in the subscription [$SUBSCRIPTION_NAME]"
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]"
		exit
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists in the subscription [$SUBSCRIPTION_NAME]"
fi

echo "Deploying Azure Container Registry and Log Analytics Workspace Bicep..."

# Validates the Bicep template
if [[ $VALIDATE_TEMPLATE == 1 ]]; then
	if [[ $USE_WHAT_IF == 1 ]]; then
		# Execute a deployment What-If operation at resource group scope.
		echo "Previewing changes deployed by Bicep template [$ACR_TEMPLATE]..."
		az deployment group what-if \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $ACR_TEMPLATE \
			--parameters $ACR_PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			--only-show-errors

		if [[ $? == 0 ]]; then
			echo "Bicep template [$ACR_TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$ACR_TEMPLATE]"
			exit
		fi
	else
		# Validate the Bicep template
		echo "Validating Bicep template [$ACR_TEMPLATE]..."
		output=$(az deployment group validate \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $ACR_TEMPLATE \
			--parameters $ACR_PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			--only-show-errors)

		if [[ $? == 0 ]]; then
			echo "Bicep template [$ACR_TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$ACR_TEMPLATE]"
			echo "$output"
			exit
		fi
	fi
fi

# Deploy the Bicep template
echo "Deploying Bicep template [$ACR_TEMPLATE]..."
if DEPLOYMENT_OUTPUTS=$(az deployment group create \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors \
	--template-file $ACR_TEMPLATE \
	--parameters $ACR_PARAMETERS \
	--parameters location=$LOCATION \
	prefix=$PREFIX \
	suffix=$SUFFIX \
	--query 'properties.outputs' -o json); then
	# Extract only the JSON portion (everything from first { to the end)
	DEPLOYMENT_JSON=$(echo "$DEPLOYMENT_OUTPUTS" | sed -n '/{/,$ p')
	echo "Bicep template [$ACR_TEMPLATE] deployed successfully. Outputs:"
	echo "$DEPLOYMENT_JSON" | jq .
	ACR_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.acrName.value')
	ACR_LOGIN_SERVER=$(echo "$DEPLOYMENT_JSON" | jq -r '.acrLoginServer.value')
	LOG_ANALYTICS_WORKSPACE_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.logAnalyticsWorkspaceName.value')
	echo "Deployment complete."
	echo "Resource Group: $RESOURCE_GROUP_NAME"
	echo "Azure Container Registry: $ACR_NAME ($ACR_LOGIN_SERVER)"
else
	echo "Failed to deploy Bicep template [$ACR_TEMPLATE]"
	exit 1
fi

if [[ -z "$ACR_NAME" || -z "$ACR_LOGIN_SERVER" || -z "$LOG_ANALYTICS_WORKSPACE_NAME" ]]; then
	echo "ACR Name, ACR Login Server, or Log Analytics Workspace Name is empty. Exiting."
	exit 1
fi

echo "Logging into Azure Container Registry [$ACR_NAME]..."
az acr login --name "$ACR_NAME" --only-show-errors

if [ $? -eq 0 ]; then
	echo "Logged into Azure Container Registry [$ACR_NAME] successfully."
else
	echo "Failed to log into Azure Container Registry [$ACR_NAME]."
	exit 1
fi

# Create full image name with login server, image name, and tag
FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building custom Docker image [$LOCAL_IMAGE]..."
docker build -t "$LOCAL_IMAGE" ../src/

if [ $? -eq 0 ]; then
	echo "Docker image [$LOCAL_IMAGE] built successfully."
else
	echo "Failed to build Docker image [$LOCAL_IMAGE]."
	exit 1
fi

echo "Tagging Docker image [$LOCAL_IMAGE] as [$FULL_IMAGE]..."
docker tag "$LOCAL_IMAGE" "$FULL_IMAGE"

if [ $? -eq 0 ]; then
	echo "Docker image [$LOCAL_IMAGE] tagged as [$FULL_IMAGE] successfully."
else
	echo "Failed to tag Docker image [$LOCAL_IMAGE] as [$FULL_IMAGE]."
	exit 1
fi

echo "Pushing image [$FULL_IMAGE] to ACR..."
docker push "$FULL_IMAGE"

if [ $? -eq 0 ]; then
	echo "Docker image [$FULL_IMAGE] pushed to ACR successfully."
else
	echo "Failed to push Docker image [$FULL_IMAGE] to ACR."
	exit 1
fi

echo "Deploying the remaining Azure resources..."

# Validates the Bicep template
if [[ $VALIDATE_TEMPLATE == 1 ]]; then
	if [[ $USE_WHAT_IF == 1 ]]; then
		# Execute a deployment What-If operation at resource group scope.
		echo "Previewing changes deployed by Bicep template [$MAIN_TEMPLATE]..."
		az deployment group what-if \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $MAIN_TEMPLATE \
			--parameters $MAIN_PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			imageName=$IMAGE_NAME \
			imageTag=$IMAGE_TAG \
			acrName="$ACR_NAME" \
			logAnalyticsWorkspaceName="$LOG_ANALYTICS_WORKSPACE_NAME" \
			--only-show-errors

		if [[ $? == 0 ]]; then
			echo "Bicep template [$MAIN_TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$MAIN_TEMPLATE]"
			exit
		fi
	else
		# Validate the Bicep template
		echo "Validating Bicep template [$MAIN_TEMPLATE]..."
		output=$(az deployment group validate \
			--resource-group $RESOURCE_GROUP_NAME \
			--template-file $MAIN_TEMPLATE \
			--parameters $MAIN_PARAMETERS \
			--parameters location=$LOCATION \
			prefix=$PREFIX \
			suffix=$SUFFIX \
			imageName=$IMAGE_NAME \
			imageTag=$IMAGE_TAG \
			acrName="$ACR_NAME" \
			logAnalyticsWorkspaceName="$LOG_ANALYTICS_WORKSPACE_NAME" \
			--only-show-errors)

		if [[ $? == 0 ]]; then
			echo "Bicep template [$MAIN_TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$MAIN_TEMPLATE]"
			echo "$output"
			exit
		fi
	fi
fi

# Deploy the Bicep template
echo "Deploying Bicep template [$MAIN_TEMPLATE]..."
if DEPLOYMENT_OUTPUTS=$(az deployment group create \
	--resource-group $RESOURCE_GROUP_NAME \
	--only-show-errors \
	--template-file $MAIN_TEMPLATE \
	--parameters $MAIN_PARAMETERS \
	--parameters location=$LOCATION \
	prefix=$PREFIX \
	suffix=$SUFFIX \
	imageName=$IMAGE_NAME \
	imageTag=$IMAGE_TAG \
	acrName="$ACR_NAME" \
	logAnalyticsWorkspaceName="$LOG_ANALYTICS_WORKSPACE_NAME" \
	--query 'properties.outputs' -o json); then
	# Extract only the JSON portion (everything from first { to the end)
	DEPLOYMENT_JSON=$(echo "$DEPLOYMENT_OUTPUTS" | sed -n '/{/,$ p')
	echo "Bicep template [$MAIN_TEMPLATE] deployed successfully. Outputs:"
	echo "$DEPLOYMENT_JSON" | jq .
	APP_SERVICE_PLAN_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.appServicePlanName.value')
	WEB_APP_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.webAppName.value')
	ACR_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.acrName.value')
	ACR_LOGIN_SERVER=$(echo "$DEPLOYMENT_JSON" | jq -r '.acrLoginServer.value')
	MANAGED_IDENTITY_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.managedIdentityName.value')
	echo "Deployment complete."
	echo "Resource Group: $RESOURCE_GROUP_NAME"
	echo "App Service Plan: $APP_SERVICE_PLAN_NAME"
	echo "Web App: $WEB_APP_NAME"
	echo "Azure Container Registry: $ACR_NAME ($ACR_LOGIN_SERVER)"
	echo "Managed Identity: $MANAGED_IDENTITY_NAME"
else
	echo "Failed to deploy Bicep template [$MAIN_TEMPLATE]"
	exit 1
fi

# Print the list of resources in the resource group
echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table 