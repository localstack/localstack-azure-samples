#!/bin/bash

# =============================================================================
# ACI Vacation Planner - Cleanup Script
#
# Removes all Azure resources created by deploy.sh and deploy-advanced.sh.
# Deletes resources in reverse order to avoid dependency issues.
# =============================================================================

# Variables (must match deploy.sh)
PREFIX='local'
RESOURCE_GROUP_NAME="${PREFIX}-aci-rg"
ACI_GROUP_NAME="${PREFIX}-aci-planner"
ACI_GROUP_ADVANCED="${PREFIX}-aci-planner-advanced"
KEY_VAULT_NAME="${PREFIX}acikv"
ACR_NAME="${PREFIX}aciacr"
STORAGE_ACCOUNT_NAME="${PREFIX}acistorage"

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	AZ="azlocal"
else
	AZ="az"
fi

echo "============================================================"
echo "Cleaning up ACI Vacation Planner Resources"
echo "============================================================"
echo ""

# 1. Delete ACI container groups (basic + advanced)
echo "[1/5] Deleting ACI container groups..."
az container delete \
	--name "$ACI_GROUP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--yes \
	--only-show-errors 2>/dev/null && echo "  Deleted: $ACI_GROUP_NAME" || echo "  Skipped: $ACI_GROUP_NAME (not found)"

az container delete \
	--name "$ACI_GROUP_ADVANCED" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--yes \
	--only-show-errors 2>/dev/null && echo "  Deleted: $ACI_GROUP_ADVANCED" || echo "  Skipped: $ACI_GROUP_ADVANCED (not found)"
echo ""

# 2. Delete ACR
echo "[2/5] Deleting ACR [$ACR_NAME]..."
az acr delete \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--yes \
	--only-show-errors 2>/dev/null && echo "  Deleted: $ACR_NAME" || echo "  Skipped: $ACR_NAME (not found)"
echo ""

# 3. Delete Key Vault (delete + purge to release the vault name)
echo "[3/5] Deleting Key Vault [$KEY_VAULT_NAME]..."
az keyvault delete \
	--name "$KEY_VAULT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors 2>/dev/null && echo "  Deleted: $KEY_VAULT_NAME" || echo "  Skipped: $KEY_VAULT_NAME (not found)"
az keyvault purge \
	--name "$KEY_VAULT_NAME" \
	--only-show-errors 2>/dev/null && echo "  Purged: $KEY_VAULT_NAME" || true
echo ""

# 4. Delete Storage Account
echo "[4/5] Deleting Storage Account [$STORAGE_ACCOUNT_NAME]..."
az storage account delete \
	--name "$STORAGE_ACCOUNT_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--yes \
	--only-show-errors 2>/dev/null && echo "  Deleted: $STORAGE_ACCOUNT_NAME" || echo "  Skipped: $STORAGE_ACCOUNT_NAME (not found)"
echo ""

# 5. Delete Resource Group
echo "[5/5] Deleting Resource Group [$RESOURCE_GROUP_NAME]..."
az group delete \
	--name "$RESOURCE_GROUP_NAME" \
	--yes \
	--only-show-errors 2>/dev/null && echo "  Deleted: $RESOURCE_GROUP_NAME" || echo "  Skipped: $RESOURCE_GROUP_NAME (not found)"
echo ""

echo "============================================================"
echo "Cleanup complete."
echo "============================================================"
