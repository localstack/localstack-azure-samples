resource "azurerm_key_vault" "vault" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  tenant_id                       = var.tenant_id
  sku_name                        = var.sku_name
  enabled_for_deployment          = var.enabled_for_deployment
  enabled_for_disk_encryption     = var.enabled_for_disk_encryption
  enabled_for_template_deployment = var.enabled_for_template_deployment
  rbac_authorization_enabled      = var.rbac_authorization_enabled
  purge_protection_enabled        = var.purge_protection_enabled
  soft_delete_retention_days      = var.soft_delete_retention_days
  public_network_access_enabled   = var.public_network_access_enabled
  tags                            = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# azurerm_key_vault_secret writes through the Key Vault data plane, so on an RBAC vault the deploying
# principal needs a data-plane role. The assignment is created here, when the caller could resolve the
# principal, and the secrets wait for it to propagate.
resource "azurerm_role_assignment" "deployer" {
  count = var.deployer_object_id == "" ? 0 : 1

  scope                = azurerm_key_vault.vault.id
  role_definition_name = var.deployer_role_definition_name
  principal_id         = var.deployer_object_id
  principal_type       = var.deployer_principal_type
}

resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.deployer]
  create_duration = var.rbac_propagation_delay
}

# One secret per entry of var.secrets. The map is sensitive because of its values; its keys are the secret
# names, which are not secret and are needed as resource keys, hence nonsensitive(keys(...)).
resource "azurerm_key_vault_secret" "secret" {
  for_each = toset(nonsensitive(keys(var.secrets)))

  name         = each.key
  value        = var.secrets[each.key]
  key_vault_id = azurerm_key_vault.vault.id
  tags         = var.tags

  depends_on = [time_sleep.rbac_propagation]
}

resource "azurerm_monitor_diagnostic_setting" "settings" {
  name                       = var.diagnostic_setting_name
  target_resource_id         = azurerm_key_vault.vault.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}
