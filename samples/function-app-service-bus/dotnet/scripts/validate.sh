#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
FUNCTION_APP_SUBNET_NSG_NAME="${PREFIX}-func-subnet-nsg-${SUFFIX}"
PE_SUBNET_NSG_NAME="${PREFIX}-pe-subnet-nsg-${SUFFIX}"
NAT_GATEWAY_NAME="${PREFIX}-nat-gateway-${SUFFIX}"
VIRTUAL_NETWORK_NAME="${PREFIX}-vnet-${SUFFIX}"
APP_SERVICE_PLAN_NAME="${PREFIX}-plan-${SUFFIX}"
FUNCTION_APP_NAME="${PREFIX}-func-${SUFFIX}"
SERVICE_BUS_NAMESPACE_NAME="${PREFIX}-service-bus-${SUFFIX}"
STORAGE_ACCOUNT_NAME="${PREFIX}storage${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-func-${SUFFIX}"
ENVIRONMENT=$(az account show --query environmentName --output tsv)
PRIVATE_DNS_ZONE_NAMES=(
	"privatelink.servicebus.windows.net"
	"privatelink.blob.core.windows.net"
	"privatelink.queue.core.windows.net"
	"privatelink.table.core.windows.net"
)
PE_NAMES=(
	"${PREFIX}-service-bus-pe-${SUFFIX}"
	"${PREFIX}-blob-storage-pe-${SUFFIX}"
	"${PREFIX}-queue-storage-pe-${SUFFIX}"
	"${PREFIX}-table-storage-pe-${SUFFIX}"
)

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	AZ="azlocal"
else
	echo "Using standard az for AzureCloud environment."
	AZ="az"
fi

# Check resource group
echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
$AZ group show \
	--name "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check App Service Plan
echo -e "\n[$APP_SERVICE_PLAN_NAME] app service plan:\n"
$AZ appservice plan show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_SERVICE_PLAN_NAME" \
	--output table \
	--only-show-errors

# Check Azure Functions App
echo -e "\n[$FUNCTION_APP_NAME] function app:\n"
$AZ functionapp show \
	--name "$FUNCTION_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Service Bus Namespace
echo -e "\n[$SERVICE_BUS_NAMESPACE_NAME] service bus namespace:\n"
$AZ servicebus namespace show \
	--name "$SERVICE_BUS_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--query '{Name:name,ServiceBusEndpoint:serviceBusEndpoint}' \
	--only-show-errors

# Check Service Bus Queues
echo -e "\n[$SERVICE_BUS_NAMESPACE_NAME] service bus queues:\n"
$AZ servicebus queue list \
	--namespace-name "$SERVICE_BUS_NAMESPACE_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--query '[].{Name:name,Status:status}' \
	--only-show-errors

	# Check Application Insights
echo -e "\n[$APPLICATION_INSIGHTS_NAME] application insights:\n"
$AZ monitor app-insights component show \
	--app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup}' \
	--output table \
	--only-show-errors

# Check Storage Account
echo -e "\n[$STORAGE_ACCOUNT_NAME] storage account:\n"
$AZ storage account show \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:primaryLocation,ResourceGroup:resourceGroup}' \
	--output table \
	--only-show-errors

# Check Log Analytics Workspace
echo -e "\n[$LOG_ANALYTICS_NAME] log analytics workspace:\n"
$AZ monitor log-analytics workspace show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--workspace-name "$LOG_ANALYTICS_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup}' \
	--output table \
	--only-show-errors

# Check NAT Gateway
echo -e "\n[$NAT_GATEWAY_NAME] nat gateway:\n"
$AZ network nat gateway show \
	--name "$NAT_GATEWAY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Virtual Network
echo -e "\n[$VIRTUAL_NETWORK_NAME] virtual network:\n"
$AZ network vnet show \
	--name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Private DNS Zone
for PRIVATE_DNS_ZONE_NAME in "${PRIVATE_DNS_ZONE_NAMES[@]}"; do
	echo -e "\n[$PRIVATE_DNS_ZONE_NAME] private dns zone:\n"
	$AZ network private-dns zone show \
		--name "$PRIVATE_DNS_ZONE_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query '{Name:name,ResourceGroup:resourceGroup,RecordSets:recordSets,VirtualNetworkLinks:virtualNetworkLinks}' \
		--output table \
		--only-show-errors
done

# Check Private Endpoint
for PRIVATE_ENDPOINT_NAME in "${PE_NAMES[@]}"; do
	echo -e "\n[$PRIVATE_ENDPOINT_NAME] private endpoint:\n"
	$AZ network private-endpoint show \
		--name "$PRIVATE_ENDPOINT_NAME" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--output table \
		--only-show-errors
done

# Check Functions App Subnet NSG
echo -e "\n[$FUNCTION_APP_SUBNET_NSG_NAME] network security group:\n"
$AZ network nsg show \
	--name "$FUNCTION_APP_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Private Endpoint Subnet NSG
echo -e "\n[$PE_SUBNET_NSG_NAME] network security group:\n"
$AZ network nsg show \
	--name "$PE_SUBNET_NSG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# List resources
echo -e "\n[$RESOURCE_GROUP_NAME] all resources:\n"
$AZ resource list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors