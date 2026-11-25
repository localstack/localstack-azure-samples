#!/bin/bash

# Variables
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
SQL_SERVER_NAME="${PREFIX}-sqlserver-${SUFFIX}"
SQL_DATABASE_NAME='PlannerDB'
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
KEY_VAULT_NAME="${PREFIX}-kv-${SUFFIX}"
SECRET_NAME="${PREFIX}-secret-${SUFFIX}"
TDE_KEY_NAME="${PREFIX}-tde-key-${SUFFIX}"
SQL_SERVER_IDENTITY_NAME="${PREFIX}-tde-identity-${SUFFIX}"
WEB_APP_IDENTITY_NAME="${PREFIX}-webapp-identity-${SUFFIX}"
APPLICATION_INSIGHTS_NAME="${PREFIX}-insights-${SUFFIX}"

# Exit with an error unless a principal holds a role on the key vault.
# $1: the principal (object) id
# $2: the role name
# $3: the description of the principal, used in messages
require_key_vault_role() {
	local count
	count=$(az role assignment list \
		--assignee "$1" \
		--scope "$KEY_VAULT_ID" \
		--query "length([?roleDefinitionName=='$2'])" \
		--output tsv \
		--only-show-errors)

	if [[ $count -ge 1 ]]; then
		echo "The $3 holds the [$2] role on the [$KEY_VAULT_NAME] key vault"
	else
		echo "The $3 does not hold the [$2] role on the [$KEY_VAULT_NAME] key vault"
		exit 1
	fi
}

# Check resource group
echo -e "[$RESOURCE_GROUP_NAME] resource group:\n"
az group show \
--name "$RESOURCE_GROUP_NAME" \
--output table

# Check Azure Web App
echo -e "\n[$WEB_APP_NAME] web app:\n"
az webapp show \
--name "$WEB_APP_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "{name:name, state:state, defaultHostName:defaultHostName}" \
--output table

# Check Azure SQL Server
echo -e "\n[$SQL_SERVER_NAME] SQL server:\n"
az sql server show \
--name "$SQL_SERVER_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--output table

# Check Azure SQL Database
echo -e "\n[$SQL_DATABASE_NAME] SQL database:\n"
az sql db show \
--name "$SQL_DATABASE_NAME" \
--server "$SQL_SERVER_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--output table

# Check that the Key Vault key is the TDE protector of the Azure SQL Server
echo -e "\n[$SQL_SERVER_NAME] SQL server TDE protector:\n"
# Read the key through Azure Resource Manager: the Bicep variant grants the caller no Key Vault data-plane access.
KEY_VAULT_ID=$(az keyvault show \
--name "$KEY_VAULT_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "id" \
--output tsv)
TDE_KEY_ID=$(az resource show \
--ids "$KEY_VAULT_ID/keys/$TDE_KEY_NAME" \
--api-version 2024-11-01 \
--query "properties.keyUriWithVersion" \
--output tsv)
TDE_PROTECTOR=$(az sql server tde-key show \
--server "$SQL_SERVER_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--output json)
echo "$TDE_PROTECTOR" | jq '{serverKeyType, uri, autoRotationEnabled}'
if [[ "$(jq -r .serverKeyType <<< "$TDE_PROTECTOR")" != "AzureKeyVault" ||
	"$(jq -r .uri <<< "$TDE_PROTECTOR")" != "$TDE_KEY_ID" ||
	"$(jq -r .autoRotationEnabled <<< "$TDE_PROTECTOR")" != "true" ]]; then
	echo "The TDE protector of [$SQL_SERVER_NAME] is not the auto-rotated Key Vault key [$TDE_KEY_ID]"
	exit 1
fi

# Check that TDE is enabled on the Azure SQL Database
TDE_STATE=$(az sql db tde show \
--database "$SQL_DATABASE_NAME" \
--server "$SQL_SERVER_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "state" \
--output tsv)
echo -e "\n[$SQL_DATABASE_NAME] SQL database TDE state: [$TDE_STATE]"
if [[ "$TDE_STATE" != "Enabled" ]]; then
	echo "TDE is not enabled on [$SQL_DATABASE_NAME]"
	exit 1
fi

# Check Azure Key Vault
echo -e "\n[$KEY_VAULT_NAME] Key Vault:\n"
az keyvault show \
--name "$KEY_VAULT_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--output table

# Check Key Vault secret
echo -e "\n[$SECRET_NAME] Key Vault secret:\n"
az keyvault secret show \
--vault-name "$KEY_VAULT_NAME" \
--name "$SECRET_NAME" \
--query "{name:name, enabled:attributes.enabled, created:attributes.created}" \
--output table

# Check that the key vault uses the Azure RBAC permission model: the role assignments below only work on such a vault
KEY_VAULT_RBAC=$(az keyvault show \
--name "$KEY_VAULT_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "properties.enableRbacAuthorization" \
--output tsv)
echo -e "\n[$KEY_VAULT_NAME] Key Vault RBAC authorization: [$KEY_VAULT_RBAC]"
if [[ $KEY_VAULT_RBAC != "true" ]]; then
	echo "The [$KEY_VAULT_NAME] key vault does not use the Azure RBAC permission model"
	exit 1
fi

# Check that the web app runs with its user-assigned managed identity, which AZURE_CLIENT_ID selects in the app
echo -e "\n[$WEB_APP_IDENTITY_NAME] managed identity of the [$WEB_APP_NAME] web app:\n"
# tr drops the carriage return the Azure CLI ends each line with on Windows: mapfile keeps it, even with bash's igncr option
mapfile -t WEB_APP_IDENTITY_FIELDS < <(az identity show \
--name "$WEB_APP_IDENTITY_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "[id, clientId, principalId]" \
--output tsv | tr -d '\r')
WEB_APP_IDENTITY_ID="${WEB_APP_IDENTITY_FIELDS[0]:-}"
WEB_APP_IDENTITY_CLIENT_ID="${WEB_APP_IDENTITY_FIELDS[1]:-}"
WEB_APP_IDENTITY_PRINCIPAL_ID="${WEB_APP_IDENTITY_FIELDS[2]:-}"
if [[ -z $WEB_APP_IDENTITY_ID || -z $WEB_APP_IDENTITY_CLIENT_ID || -z $WEB_APP_IDENTITY_PRINCIPAL_ID ]]; then
	echo "Failed to retrieve the [$WEB_APP_IDENTITY_NAME] managed identity"
	exit 1
fi
if az webapp identity show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query "keys(userAssignedIdentities || \`{}\`)" \
	--output tsv | tr -d '\r' | grep -q -i -x -F "$WEB_APP_IDENTITY_ID"; then
	echo "The [$WEB_APP_NAME] web app uses the [$WEB_APP_IDENTITY_NAME] managed identity"
else
	echo "The [$WEB_APP_NAME] web app does not use the [$WEB_APP_IDENTITY_NAME] managed identity"
	exit 1
fi
AZURE_CLIENT_ID_SETTING=$(az webapp config appsettings list \
--name "$WEB_APP_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "[?name=='AZURE_CLIENT_ID'].value | [0]" \
--output tsv)
if [[ $AZURE_CLIENT_ID_SETTING == "$WEB_APP_IDENTITY_CLIENT_ID" ]]; then
	echo "The AZURE_CLIENT_ID app setting holds the client id of the [$WEB_APP_IDENTITY_NAME] managed identity"
else
	echo "The AZURE_CLIENT_ID app setting [$AZURE_CLIENT_ID_SETTING] is not the client id [$WEB_APP_IDENTITY_CLIENT_ID] of the [$WEB_APP_IDENTITY_NAME] managed identity"
	exit 1
fi

# Check the roles of the managed identities on the key vault: the web app reads the connection string and the private
# key of its certificate as secrets, and the certificate itself; the SQL server wraps and unwraps its database
# encryption keys with the TDE protector key
echo -e "\n[$KEY_VAULT_NAME] Key Vault role assignments:\n"
SQL_SERVER_IDENTITY_PRINCIPAL_ID=$(az identity show \
--name "$SQL_SERVER_IDENTITY_NAME" \
--resource-group "$RESOURCE_GROUP_NAME" \
--query "principalId" \
--output tsv)
if [[ -z $SQL_SERVER_IDENTITY_PRINCIPAL_ID ]]; then
	echo "Failed to retrieve the principalId of the [$SQL_SERVER_IDENTITY_NAME] managed identity"
	exit 1
fi
require_key_vault_role "$WEB_APP_IDENTITY_PRINCIPAL_ID" "Key Vault Secrets User" "[$WEB_APP_IDENTITY_NAME] managed identity"
require_key_vault_role "$WEB_APP_IDENTITY_PRINCIPAL_ID" "Key Vault Certificate User" "[$WEB_APP_IDENTITY_NAME] managed identity"
require_key_vault_role "$SQL_SERVER_IDENTITY_PRINCIPAL_ID" "Key Vault Crypto Service Encryption User" "[$SQL_SERVER_IDENTITY_NAME] managed identity"

# Check Application Insights component
echo -e "\n[$APPLICATION_INSIGHTS_NAME] Application Insights component:\n"
az monitor app-insights component show \
	--app "$APPLICATION_INSIGHTS_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--query '{Name:name,Location:location,ResourceGroup:resourceGroup,ApplicationType:applicationType,WorkspaceResourceId:workspaceResourceId}' \
	--output table \
	--only-show-errors

# Print the list of resources in the resource group
echo -e "\nListing resources in resource group [$RESOURCE_GROUP_NAME]...\n"
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table 
