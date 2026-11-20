resource "azurerm_key_vault" "example" {
  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = var.tenant_id
  sku_name                   = var.sku_name
  rbac_authorization_enabled = false
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled
  tags                       = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Grant the identity running Terraform access to manage the Key Vault key, secret and certificate
resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = azurerm_key_vault.example.id
  tenant_id    = var.tenant_id
  object_id    = var.deployer_object_id

  key_permissions = [
    "Create",
    "Delete",
    "Get",
    "GetRotationPolicy",
  ]

  secret_permissions = [
    "Delete",
    "Get",
    "Set",
  ]

  certificate_permissions = [
    "Create",
    "Delete",
    "Get",
  ]
}

# Grant the SQL server managed identity access to the TDE protector key
resource "azurerm_key_vault_access_policy" "sql_server" {
  key_vault_id = azurerm_key_vault.example.id
  tenant_id    = var.tenant_id
  object_id    = var.sql_server_identity_principal_id

  key_permissions = [
    "Get",
    "UnwrapKey",
    "WrapKey",
  ]
}

# Create the RSA key that protects the database encryption keys of the SQL server
resource "azurerm_key_vault_key" "tde" {
  name         = var.tde_key_name
  key_vault_id = azurerm_key_vault.example.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["unwrapKey", "wrapKey"]

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

# Create a Key Vault secret for SQL connection string
resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = var.secret_name
  value        = "Server=tcp:${var.sql_server_fqdn},1433;Database=${var.sql_database_name};User ID=${var.sql_database_username};Password=${var.sql_database_password};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.example.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
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

  depends_on = [azurerm_key_vault_access_policy.deployer]
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
