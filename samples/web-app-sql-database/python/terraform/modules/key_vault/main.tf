resource "azurerm_key_vault" "example" {
  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = var.tenant_id
  sku_name                   = var.sku_name
  rbac_authorization_enabled = var.rbac_authorization_enabled
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled
  tags                       = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# azurerm_key_vault_key, azurerm_key_vault_secret and azurerm_key_vault_certificate write through the Key Vault data
# plane, so on an RBAC vault the principal running Terraform needs a data-plane role for each: Key Vault Crypto
# Officer, Secrets Officer and Certificates Officer by default. They are assigned here, when the caller could resolve
# the principal, and the key, the secret and the certificate wait for them to propagate.
resource "azurerm_role_assignment" "deployer" {
  for_each = var.deployer_object_id == "" ? toset([]) : toset(var.deployer_role_definition_names)

  scope                = azurerm_key_vault.example.id
  role_definition_name = each.value
  principal_id         = var.deployer_object_id
  principal_type       = var.deployer_principal_type
}

resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.deployer]
  create_duration = var.rbac_propagation_delay
}

# Create the RSA key that protects the database encryption keys of the SQL server
resource "azurerm_key_vault_key" "tde" {
  name         = var.tde_key_name
  key_vault_id = azurerm_key_vault.example.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["unwrapKey", "wrapKey"]

  depends_on = [time_sleep.rbac_propagation]
}

# Create a Key Vault secret for SQL connection string
resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = var.secret_name
  value        = "Server=tcp:${var.sql_server_fqdn},1433;Database=${var.sql_database_name};User ID=${var.sql_database_username};Password=${var.sql_database_password};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.example.id

  depends_on = [time_sleep.rbac_propagation]
}

# Create a self-signed certificate in Key Vault: the web app serves HTTPS with it on port 8443
resource "azurerm_key_vault_certificate" "example" {
  name         = var.cert_name
  key_vault_id = azurerm_key_vault.example.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = "CN=${var.cert_subject}"
      validity_in_months = 12

      key_usage = [
        "digitalSignature",
        "keyEncipherment",
      ]
    }
  }

  depends_on = [time_sleep.rbac_propagation]
}

resource "azurerm_monitor_diagnostic_setting" "example" {
  name                           = var.diagnostic_setting_name
  target_resource_id             = azurerm_key_vault.example.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = var.log_analytics_destination_type

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
