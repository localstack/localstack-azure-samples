# Azure CLI Deployment

This directory contains the Azure CLI scripts for provisioning Azure services in LocalStack for Azure. For further details about the sample application, refer to the [Azure Web App with Custom Docker Image](../README.md).

## Prerequisites

Before deploying this solution, ensure you have the following tools installed:

- [LocalStack for Azure](https://docs.localstack.cloud/azure/): Local Azure cloud emulator for development and testing
- [Docker](https://docs.docker.com/get-docker/): Container runtime required for LocalStack and building the custom image
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli): Azure command-line interface
- [Azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/): LocalStack Azure CLI wrapper
- [Python](https://www.python.org/downloads/): Python runtime (version 3.12 or above)
- [jq](https://jqlang.org/): JSON processor for scripting and parsing command outputs

### Installing azlocal CLI

The [deploy.sh](deploy.sh) Bash script uses the `azlocal` CLI instead of the standard Azure CLI to work with LocalStack. Install it using:

```bash
pip install azlocal
```

For more information, see [Get started with the az tool on LocalStack](https://azure.localstack.cloud/user-guides/sdks/az/).

## Architecture Overview

The [deploy.sh](deploy.sh) script creates all Azure resources from scratch using the Azure CLI:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli): A logical container scoping all resources in this sample.
2. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview): Hosts two subnets:
	- *app-subnet*: Dedicated to [regional VNet integration](https://learn.microsoft.com/azure/azure-functions/functions-networking-options?tabs=azure-portal#outbound-networking-features) with the Web App.
	- *pe-subnet*: Used for hosting Azure Private Endpoints.
3. [Azure Private DNS Zone](https://learn.microsoft.com/azure/dns/private-dns-privatednszone): Handles DNS resolution for the Azure Container Registry Private Endpoint within the virtual network.
4. [Azure Private Endpoint](https://learn.microsoft.com/azure/private-link/private-endpoint-overview): Secures network access to the Azure Container Registry via a private IP within the VNet.
5. [Azure NAT Gateway](https://learn.microsoft.com/azure/nat-gateway/nat-overview): Provides deterministic outbound connectivity for the Web App. Included for completeness; the sample app does not call any external services.
6. [Azure Network Security Group](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview): Enforces inbound and outbound traffic rules across the virtual network's subnets.
7. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview): Centralizes diagnostic logs and metrics from all resources in the solution.
8. [Azure Container Registry](https://learn.microsoft.com/azure/container-registry/container-registry-intro): A fully-managed container registry service based on the open-source [Docker platform](https://docs.docker.com/get-started/docker-overview/) used to hold the container image used by the web app.
9. [User-Assigned Managed Identity](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview): Assigned the [AcrPull](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/containers#acrpull) role on the Azure Container Registry, enabling the Web App to pull the container image without storing credentials.
10. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans): The underlying compute tier that hosts the web application.
11. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview): Runs the Python Flask application from the custom container image stored in the Azure Container Registry.

## Provisioning Scripts

See [deploy.sh](deploy.sh) for the complete deployment automation. The script performs:

- Creates resource group
- Deploys Azure Container Registry
- Builds container image locally and pushes it to ACR
- Deploys remaining Azure resources (VNet, NSG, NAT Gateway, DNS, Private Endpoint, App Service Plan, managed identity, Web App)
- Configures Web App to use the container image from ACR
- Assigns [AcrPull](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/containers#acrpull) role to the user-assigned managed identity

## Deployment

You can set up the Azure emulator by utilizing the LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/?__hstc=108988063.8aad2b1a7229945859f4d9b9bb71e05d.1743148429561.1758793541854.1758810151462.32&__hssc=108988063.3.1758810151462&__hsfp=3945774529) to obtain your Auth Token and specify it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure-alpha). To pull the Azure Docker image, execute the following command:

```bash
docker pull localstack/localstack-azure-alpha
```

Start the LocalStack Azure emulator using the localstack CLI, execute the following command:

```bash
# Set the authentication token
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>

# Start the LocalStack Azure emulator
IMAGE_NAME=localstack/localstack-azure-alpha localstack start -d
localstack wait -t 60

# Route all Azure CLI calls to the LocalStack Azure emulator
azlocal start-interception
```

Navigate to the `scripts` folder:

```bash
cd samples/web-app-custom-image/python/scripts
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

Once the deployment completes, run the [validate.sh](validate.sh) script to confirm that all resources were provisioned and configured as expected:

```bash
#!/bin/bash
set -euo pipefail

PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
ACR_NAME="${PREFIX}acr${SUFFIX}"
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
VIRTUAL_NETWORK_NAME="${PREFIX}-vnet-${SUFFIX}"
PRIVATE_DNS_ZONE_NAME="privatelink.azurecr.io"
PRIVATE_ENDPOINT_NAME="${PREFIX}-acr-pe-${SUFFIX}"
WEB_APP_SUBNET_NSG_NAME="${PREFIX}-webapp-subnet-nsg-${SUFFIX}"
PE_SUBNET_NSG_NAME="${PREFIX}-pe-subnet-nsg-${SUFFIX}"
NAT_GATEWAY_NAME="${PREFIX}-nat-gateway-${SUFFIX}"
PIP_PREFIX_NAME="${PREFIX}-nat-gateway-pip-prefix-${SUFFIX}"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"

# Check resource group
echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
az group show \
	--name "$RESOURCE_GROUP_NAME" \
	--output table

# Check managed identity
echo -e "[$MANAGED_IDENTITY_NAME] managed identity:\n"
az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table

# Check App Service Plan
echo -e "\n[$APP_SERVICE_PLAN_NAME] App Service Plan:\n"
az appservice plan show \
	--name "$APP_SERVICE_PLAN_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table

# Check Azure Container Registry
echo -e "\n[$ACR_NAME] Azure Container Registry:\n"
az acr show \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table

# Check Azure Web App
echo -e "\n[$WEB_APP_NAME] Web App:\n"
az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "{name:name, state:state, defaultHostName:defaultHostName, kind:kind}" \
	--output table

# Check App Settings
echo -e "\n[$WEB_APP_NAME] app settings:\n"
az webapp config appsettings list \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[?name=='IMAGE_NAME' || name=='APP_NAME' || name=='WEBSITES_PORT']" \
	--output table

# Check Virtual Network
echo -e "\n[$VIRTUAL_NETWORK_NAME] virtual network:\n"
az network vnet show \
	--name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Private DNS Zone
echo -e "\n[$PRIVATE_DNS_ZONE_NAME] private dns zone:\n"
az network private-dns zone show \
	--name "$PRIVATE_DNS_ZONE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,ResourceGroup:resourceGroup,RecordSets:recordSets,VirtualNetworkLinks:virtualNetworkLinks}' \
	--output table \
	--only-show-errors

# Check Private Endpoint
echo -e "\n[$PRIVATE_ENDPOINT_NAME] private endpoint:\n"
az network private-endpoint show \
	--name "$PRIVATE_ENDPOINT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Web App Subnet NSG
echo -e "\n[$WEB_APP_SUBNET_NSG_NAME] network security group:\n"
az network nsg show \
	--name "$WEB_APP_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Private Endpoint Subnet NSG
echo -e "\n[$PE_SUBNET_NSG_NAME] network security group:\n"
az network nsg show \
	--name "$PE_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check NAT Gateway
echo -e "\n[$NAT_GATEWAY_NAME] nat gateway:\n"
az network nat gateway show \
	--name "$NAT_GATEWAY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Public IP Prefix
echo -e "\n[$PIP_PREFIX_NAME] public ip prefix:\n"
az network public-ip prefix show \
	--name "$PIP_PREFIX_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Log Analytics Workspace
echo -e "\n[$LOG_ANALYTICS_NAME] log analytics workspace:\n"
az monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup}' \
	--output table \
	--only-show-errors

echo -e "\nResources in [$RESOURCE_GROUP_NAME]:\n"
az resource list \
	--resource-group "$RESOURCE_GROUP_NAME" \
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

This will remove all Azure resources created by the Azure CLI deployment script.

## Related Documentation

- [Azure CLI Documentation](https://learn.microsoft.com/en-us/cli/azure/)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
