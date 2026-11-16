#!/bin/bash

# Variables (the same defaults and environment overrides as deploy.sh)
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
LOG_ANALYTICS_NAME="${PREFIX}-log-analytics-${SUFFIX}"
WEB_APP_SUBNET_NSG_NAME="${PREFIX}-webapp-subnet-nsg-${SUFFIX}"
PE_SUBNET_NSG_NAME="${PREFIX}-pe-subnet-nsg-${SUFFIX}"
NAT_GATEWAY_NAME="${PREFIX}-nat-gateway-${SUFFIX}"
VIRTUAL_NETWORK_NAME="${PREFIX}-vnet-${SUFFIX}"
VIRTUAL_NETWORK_LINK_NAME="link-to-vnet"
PRIVATE_DNS_ZONE_GROUP_NAME="default"
POSTGRES_PRIVATE_DNS_ZONE_NAME="privatelink.postgres.database.azure.com"
POSTGRES_PRIVATE_ENDPOINT_NAME="${PREFIX}-postgres-pe-${SUFFIX}"
APP_CONFIG_NAME="${PREFIX}-appconfig-${SUFFIX}"
APP_CONFIG_PRIVATE_DNS_ZONE_NAME="privatelink.azconfig.io"
APP_CONFIG_PRIVATE_ENDPOINT_NAME="${PREFIX}-appconfig-pe-${SUFFIX}"
KEY_VAULT_NAME="${PREFIX}-keyvault-${SUFFIX}"
KEY_VAULT_PRIVATE_DNS_ZONE_NAME="privatelink.vaultcore.azure.net"
KEY_VAULT_PRIVATE_ENDPOINT_NAME="${PREFIX}-keyvault-pe-${SUFFIX}"
MANAGED_IDENTITY_NAME="${PREFIX}-identity-${SUFFIX}"
APP_SERVICE_PLAN_NAME="${PREFIX}-app-service-plan-${SUFFIX}"
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
POSTGRES_SERVER_NAME="${PREFIX}-pgflex-${SUFFIX}"
POSTGRES_DATABASE_NAME="${PG_DATABASE_NAME:-PlannerDB}"
FIREWALL_RULE_NAME="AllowAllIPs"
EXIT_CODE=0

# Show a private DNS zone, its link to the virtual network, a private endpoint and its DNS zone group
# $1: the zone name
# $2: the private endpoint name
show_private_link() {
	local zone_name=$1
	local endpoint_name=$2

	echo -e "\n[$zone_name] private dns zone:\n"
	az network private-dns zone show \
		--name "$zone_name" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query '{Name:name,ResourceGroup:resourceGroup,RecordSets:numberOfRecordSets,VirtualNetworkLinks:numberOfVirtualNetworkLinks}' \
		--output table \
		--only-show-errors

	echo -e "\n[$VIRTUAL_NETWORK_LINK_NAME] virtual network link of the [$zone_name] private dns zone:\n"
	az network private-dns link vnet show \
		--name "$VIRTUAL_NETWORK_LINK_NAME" \
		--zone-name "$zone_name" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query '{Name:name,VirtualNetwork:virtualNetwork.id,RegistrationEnabled:registrationEnabled,LinkState:virtualNetworkLinkState}' \
		--output table \
		--only-show-errors

	echo -e "\n[$endpoint_name] private endpoint:\n"
	az network private-endpoint show \
		--name "$endpoint_name" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query '{Name:name,Subnet:subnet.id,GroupIds:join(`,`, privateLinkServiceConnections[0].groupIds),Target:privateLinkServiceConnections[0].privateLinkServiceId}' \
		--output table \
		--only-show-errors

	echo -e "\n[$PRIVATE_DNS_ZONE_GROUP_NAME] private dns zone group of the [$endpoint_name] private endpoint:\n"
	az network private-endpoint dns-zone-group show \
		--name "$PRIVATE_DNS_ZONE_GROUP_NAME" \
		--endpoint-name "$endpoint_name" \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--query '{Name:name,Zones:join(`,`, privateDnsZoneConfigs[].privateDnsZoneId)}' \
		--output table \
		--only-show-errors
}

# Check resource group
echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
az group show \
	--name "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check the user-assigned managed identity
echo -e "\n[$MANAGED_IDENTITY_NAME] user-assigned managed identity:\n"
az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ClientId:clientId,PrincipalId:principalId}' \
	--output table \
	--only-show-errors

IDENTITY_PRINCIPAL_ID=$(az identity show \
	--name "$MANAGED_IDENTITY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query principalId \
	--output tsv \
	--only-show-errors)

# Check the App Configuration store
echo -e "\n[$APP_CONFIG_NAME] App Configuration store:\n"
az appconfig show \
	--name "$APP_CONFIG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,Endpoint:endpoint,Sku:sku.name,LocalAuthDisabled:disableLocalAuth,PublicNetworkAccess:publicNetworkAccess}' \
	--output table \
	--only-show-errors

APP_CONFIG_ID=$(az appconfig show \
	--name "$APP_CONFIG_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

# Check the key-values: PG_HOST, PG_PORT and PG_DATABASE are plain values, PG_USER and PG_PASSWORD are
# Key Vault references (content type application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8).
# The projection uses --query instead of --fields, which would make the CLI request only those fields and
# then fail to build a Key Vault reference whose value was not returned.
echo -e "\nKey-values in the [$APP_CONFIG_NAME] App Configuration store:\n"
az appconfig kv list \
	--name "$APP_CONFIG_NAME" \
	--query "[].{Key:key,ContentType:contentType,Label:label}" \
	--output table \
	--only-show-errors

# Check the key vault
echo -e "\n[$KEY_VAULT_NAME] key vault:\n"
az keyvault show \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,VaultUri:properties.vaultUri,RbacAuthorization:properties.enableRbacAuthorization,SoftDelete:properties.enableSoftDelete,PublicNetworkAccess:properties.publicNetworkAccess}' \
	--output table \
	--only-show-errors

KEY_VAULT_ID=$(az keyvault show \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query id \
	--output tsv \
	--only-show-errors)

# Check the secret names (never the values)
echo -e "\nSecrets in the [$KEY_VAULT_NAME] key vault (names only):\n"
az keyvault secret list \
	--vault-name "$KEY_VAULT_NAME" \
	--query '[].{Name:name,Enabled:attributes.enabled,ContentType:contentType}' \
	--output table \
	--only-show-errors

# Check the role assignments of the managed identity
echo -e "\nRole assignments of the [$MANAGED_IDENTITY_NAME] managed identity on the [$APP_CONFIG_NAME] App Configuration store:\n"
az role assignment list \
	--assignee "$IDENTITY_PRINCIPAL_ID" \
	--scope "$APP_CONFIG_ID" \
	--query '[].{Role:roleDefinitionName,PrincipalType:principalType,Scope:scope}' \
	--output table \
	--only-show-errors

echo -e "\nRole assignments of the [$MANAGED_IDENTITY_NAME] managed identity on the [$KEY_VAULT_NAME] key vault:\n"
az role assignment list \
	--assignee "$IDENTITY_PRINCIPAL_ID" \
	--scope "$KEY_VAULT_ID" \
	--query '[].{Role:roleDefinitionName,PrincipalType:principalType,Scope:scope}' \
	--output table \
	--only-show-errors

# Check App Service Plan
echo -e "\n[$APP_SERVICE_PLAN_NAME] app service plan:\n"
az appservice plan show \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$APP_SERVICE_PLAN_NAME" \
	--output table \
	--only-show-errors

# Check Azure Web App
echo -e "\n[$WEB_APP_NAME] web app:\n"
az webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,State:state,Location:location,DefaultHostName:defaultHostName,IdentityType:identity.type}' \
	--output table \
	--only-show-errors

# Check the app settings: the store endpoint and the identity client id are present, no PG_* setting is
echo -e "\nApp settings of the [$WEB_APP_NAME] web app:\n"
az webapp config appsettings list \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[?name!='AZURE_CLIENT_ID'].{Name:name,Value:value} | [?Name!='Endpoints__AppConfiguration'] | [].{Name:Name,Value:Value}" \
	--output table \
	--only-show-errors

PG_SETTINGS=$(az webapp config appsettings list \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[?starts_with(name, 'PG_')].name" \
	--output tsv \
	--only-show-errors)

if [[ -n $PG_SETTINGS ]]; then
	echo -e "\nERROR: the [$WEB_APP_NAME] web app has plaintext PostgreSQL settings in its app settings: $(echo "$PG_SETTINGS" | tr '\n' ' ')"
	echo "The connection settings must come from the [$APP_CONFIG_NAME] App Configuration store only."
	EXIT_CODE=1
else
	echo -e "\nOK: no PG_* app setting exists on the [$WEB_APP_NAME] web app; the connection settings come from the [$APP_CONFIG_NAME] App Configuration store."
fi

REQUIRED_SETTINGS=$(az webapp config appsettings list \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "[?name=='Endpoints__AppConfiguration' || name=='AZURE_CLIENT_ID'].name" \
	--output tsv \
	--only-show-errors | sort | tr '\n' ' ')

if [[ $REQUIRED_SETTINGS == "AZURE_CLIENT_ID Endpoints__AppConfiguration " ]]; then
	echo "OK: the [$WEB_APP_NAME] web app has the Endpoints__AppConfiguration and AZURE_CLIENT_ID app settings."
else
	echo "ERROR: the [$WEB_APP_NAME] web app is missing the Endpoints__AppConfiguration or the AZURE_CLIENT_ID app setting (found: $REQUIRED_SETTINGS)."
	EXIT_CODE=1
fi

# Check Azure Database for PostgreSQL flexible server
echo -e "\n[$POSTGRES_SERVER_NAME] PostgreSQL flexible server:\n"
az postgres flexible-server show \
	--name "$POSTGRES_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,State:state,Version:version,FQDN:fullyQualifiedDomainName,PublicNetworkAccess:network.publicNetworkAccess}' \
	--output table \
	--only-show-errors

# Check PostgreSQL database
echo -e "\n[$POSTGRES_DATABASE_NAME] PostgreSQL database:\n"
az postgres flexible-server db show \
	--server-name "$POSTGRES_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$POSTGRES_DATABASE_NAME" \
	--query '{Name:name,ResourceGroup:resourceGroup,Charset:charset,Collation:collation}' \
	--output table \
	--only-show-errors

# Check PostgreSQL firewall rule
echo -e "\n[$FIREWALL_RULE_NAME] PostgreSQL firewall rule:\n"
az postgres flexible-server firewall-rule show \
	--server-name "$POSTGRES_SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$FIREWALL_RULE_NAME" \
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

# Check NAT Gateway
echo -e "\n[$NAT_GATEWAY_NAME] nat gateway:\n"
az network nat gateway show \
	--name "$NAT_GATEWAY_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check Virtual Network
echo -e "\n[$VIRTUAL_NETWORK_NAME] virtual network:\n"
az network vnet show \
	--name "$VIRTUAL_NETWORK_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

# Check the three private DNS zones, links, private endpoints and zone groups
show_private_link "$POSTGRES_PRIVATE_DNS_ZONE_NAME" "$POSTGRES_PRIVATE_ENDPOINT_NAME"
show_private_link "$APP_CONFIG_PRIVATE_DNS_ZONE_NAME" "$APP_CONFIG_PRIVATE_ENDPOINT_NAME"
show_private_link "$KEY_VAULT_PRIVATE_DNS_ZONE_NAME" "$KEY_VAULT_PRIVATE_ENDPOINT_NAME"

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

# List resources
echo -e "\n[$RESOURCE_GROUP_NAME] all resources:\n"
az resource list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--output table \
	--only-show-errors

exit $EXIT_CODE
