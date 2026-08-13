#!/bin/bash

# =============================================================================
# Container Apps Guestbook - Cleanup Script
#
# Removes all Azure resources created by deploy.sh.
# Deletes resources in reverse order to avoid dependency issues.
# =============================================================================

# Variables (must match deploy.sh)
PREFIX='local'
RESOURCE_GROUP_NAME="${PREFIX}-aca-rg"
ACA_APP_NAME="${PREFIX}-aca-guestbook"
ACA_ENV_NAME="${PREFIX}-aca-env"
ACR_NAME="${PREFIX}acaacr"
STORAGE_ACCOUNT_NAME="${PREFIX}acastorage"

echo "============================================================"
echo "Cleaning up Container Apps Guestbook Resources"
echo "============================================================"
echo ""

# 1. Delete the container app
echo "[1/5] Deleting container app [$ACA_APP_NAME]..."
az containerapp delete \
	--name "$ACA_APP_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--yes \
	--only-show-errors 2>/dev/null && echo "  Deleted: $ACA_APP_NAME" || echo "  Skipped: $ACA_APP_NAME (not found)"
echo ""

# 2. Delete the Container Apps environment
echo "[2/5] Deleting Container Apps environment [$ACA_ENV_NAME]..."
az containerapp env delete \
	--name "$ACA_ENV_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--yes \
	--only-show-errors 2>/dev/null && echo "  Deleted: $ACA_ENV_NAME" || echo "  Skipped: $ACA_ENV_NAME (not found)"
echo ""

# 3. Delete ACR
echo "[3/5] Deleting ACR [$ACR_NAME]..."
az acr delete \
	--name "$ACR_NAME" \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--yes \
	--only-show-errors 2>/dev/null && echo "  Deleted: $ACR_NAME" || echo "  Skipped: $ACR_NAME (not found)"
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
