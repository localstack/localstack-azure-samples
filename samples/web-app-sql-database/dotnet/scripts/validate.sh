#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
RESOURCE_GROUP_NAME="${PREFIX}-rg"
SQL_SERVER_NAME="${PREFIX}-sqlserver-${SUFFIX}"
SQL_DATABASE_NAME='PlannerDB'
WEB_APP_NAME="${PREFIX}-webapp-${SUFFIX}"
KEY_VAULT_NAME="${PREFIX}-kv-${SUFFIX}"
SECRET_NAME="${PREFIX}-secret-${SUFFIX}"
TDE_KEY_NAME="${PREFIX}-tde-key-${SUFFIX}"

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

# Print the list of resources in the resource group
echo -e "\nListing resources in resource group [$RESOURCE_GROUP_NAME]...\n"
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table 
