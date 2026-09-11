variable "prefix" {
  description = "Prefix for the name of the Azure resources."
  type        = string
  default     = "local"

  validation {
    condition     = var.prefix == null || length(var.prefix) >= 2
    error_message = "The prefix must be at least 2 characters long."
  }
}

variable "suffix" {
  description = "Suffix for the name of the Azure resources. The App Configuration store and the Key Vault have globally unique names, so use your own suffix on Azure."
  type        = string
  default     = "test"

  validation {
    condition     = var.suffix == null || length(var.suffix) >= 2
    error_message = "The suffix must be at least 2 characters long."
  }
}

variable "location" {
  description = "Specifies the location for all resources."
  type        = string
  default     = "westeurope"
}

# -----------------------------------------------------------------------------
# PostgreSQL flexible server
# -----------------------------------------------------------------------------
variable "pg_admin_login" {
  description = "Administrator login for the PostgreSQL flexible server. Only used by the post-apply psql bootstrap; the Web App never authenticates with this account."
  type        = string
  default     = "pgadmin"
}

variable "pg_admin_password" {
  description = "Administrator password for the PostgreSQL flexible server. Pass via -var or the PG_ADMIN_PASSWORD env var; do NOT commit."
  type        = string
  sensitive   = true
  default     = "P@ssw0rd1234!"
}

variable "pg_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"

  validation {
    condition     = contains(["13", "14", "15", "16", "17"], var.pg_version)
    error_message = "The pg_version must be one of: 13, 14, 15, 16, 17."
  }
}

variable "pg_sku_name" {
  description = "Compute SKU for the PostgreSQL flexible server (e.g. B_Standard_B1ms)."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "pg_storage_mb" {
  description = "Storage size in MB for the PostgreSQL flexible server."
  type        = number
  default     = 32768
}

variable "pg_backup_retention_days" {
  description = "Backup retention period in days for the PostgreSQL flexible server."
  type        = number
  default     = 7
}

variable "pg_database_name" {
  description = "Name of the application database to create on the PostgreSQL flexible server."
  type        = string
  default     = "PlannerDB"
}

variable "pg_app_user" {
  description = "Name of the PostgreSQL application role the Web App connects with. Stored in Key Vault as the pg-user secret; the role itself is created by the post-apply psql bootstrap."
  type        = string
  default     = "testuser"
}

variable "pg_app_password" {
  description = "Password of the PostgreSQL application role. Stored in Key Vault as the pg-password secret. Pass via -var or the PG_APP_PASSWORD env var; do NOT commit."
  type        = string
  sensitive   = true
  default     = "TestP@ssw0rd123"
}

# -----------------------------------------------------------------------------
# App Configuration and Key Vault
# -----------------------------------------------------------------------------
variable "app_configuration_sku" {
  description = "SKU of the App Configuration store. Private endpoints need developer, standard or premium."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["developer", "standard", "premium"], var.app_configuration_sku)
    error_message = "The app_configuration_sku must be developer, standard or premium."
  }
}

variable "key_vault_sku_name" {
  description = "SKU of the Key Vault."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku_name)
    error_message = "The key_vault_sku_name must be standard or premium."
  }
}

variable "soft_delete_retention_days" {
  description = "For how many days a deleted App Configuration store or Key Vault stays recoverable."
  type        = number
  default     = 7
}

variable "app_configuration_local_auth_enabled" {
  description = "Whether the App Configuration store keeps its access keys enabled. The key-values are written through Azure Resource Manager, which in the default Local authentication mode relies on them."
  type        = bool
  default     = true
}

variable "app_configuration_public_network_access" {
  description = "Whether the App Configuration store accepts requests from public networks (Enabled or Disabled). The deployment seeds the store from outside the virtual network; the Web App reaches it through the private endpoint."
  type        = string
  default     = "Enabled"

  validation {
    condition     = contains(["Enabled", "Disabled"], var.app_configuration_public_network_access)
    error_message = "The app_configuration_public_network_access must be Enabled or Disabled."
  }
}

variable "app_configuration_purge_protection_enabled" {
  description = "Whether purge protection is enabled on the App Configuration store. Off so that a destroyed store can be purged and its name reused."
  type        = bool
  default     = false
}

variable "key_vault_rbac_authorization_enabled" {
  description = "Whether the Key Vault uses the Azure RBAC permission model. Required: Key Vault Secrets User and Key Vault Secrets Officer only work with it."
  type        = bool
  default     = true
}

variable "key_vault_public_network_access_enabled" {
  description = "Whether the Key Vault accepts requests from public networks. The deployment writes the secrets from outside the virtual network; the Web App reaches the vault through the private endpoint."
  type        = bool
  default     = true
}

variable "key_vault_purge_protection_enabled" {
  description = "Whether purge protection is enabled on the Key Vault. Off so that a destroyed vault can be purged and its name reused."
  type        = bool
  default     = false
}

variable "pg_user_secret_name" {
  description = "Name of the Key Vault secret holding the PostgreSQL application role name (alphanumerics and hyphens only)."
  type        = string
  default     = "pg-user"
}

variable "pg_password_secret_name" {
  description = "Name of the Key Vault secret holding the PostgreSQL application role password (alphanumerics and hyphens only)."
  type        = string
  default     = "pg-password"
}

variable "pg_host_key_name" {
  description = "Key of the App Configuration key-value holding the PostgreSQL host name. The application reads this key."
  type        = string
  default     = "PG_HOST"
}

variable "pg_port_key_name" {
  description = "Key of the App Configuration key-value holding the PostgreSQL port. The application reads this key."
  type        = string
  default     = "PG_PORT"
}

variable "pg_database_key_name" {
  description = "Key of the App Configuration key-value holding the PostgreSQL database name. The application reads this key."
  type        = string
  default     = "PG_DATABASE"
}

variable "pg_user_key_name" {
  description = "Key of the App Configuration Key Vault reference to the application role name secret. The application reads this key."
  type        = string
  default     = "PG_USER"
}

variable "pg_password_key_name" {
  description = "Key of the App Configuration Key Vault reference to the application role password secret. The application reads this key."
  type        = string
  default     = "PG_PASSWORD"
}

variable "key_vault_reference_content_type" {
  description = "Content type that marks an App Configuration key-value as a Key Vault reference."
  type        = string
  default     = "application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8"
}

variable "pg_default_port" {
  description = "PostgreSQL port stored in the PG_PORT key-value when the server's fully qualified domain name carries none (Azure); the emulator's name carries the port of its TCP proxy."
  type        = string
  default     = "5432"
}

variable "app_configuration_data_reader_role_name" {
  description = "Role assigned to the Web App identity on the App Configuration store."
  type        = string
  default     = "App Configuration Data Reader"
}

variable "key_vault_secrets_user_role_name" {
  description = "Role assigned to the Web App identity on the Key Vault."
  type        = string
  default     = "Key Vault Secrets User"
}

variable "managed_identity_principal_type" {
  description = "Principal type of the Web App's user-assigned managed identity in its role assignments."
  type        = string
  default     = "ServicePrincipal"
}

variable "deployer_object_id" {
  description = "Object id of the principal running terraform apply. It is granted Key Vault Secrets Officer on the vault so azurerm_key_vault_secret can write the secrets on an RBAC vault. Empty skips the assignment (deploy.sh resolves it)."
  type        = string
  default     = ""
}

variable "deployer_principal_type" {
  description = "Principal type of the deploying principal: User, ServicePrincipal or Group."
  type        = string
  default     = "User"

  validation {
    condition     = contains(["User", "ServicePrincipal", "Group"], var.deployer_principal_type)
    error_message = "The deployer_principal_type must be User, ServicePrincipal or Group."
  }
}

variable "deployer_role_definition_name" {
  description = "Role granted to the deploying principal on the Key Vault so that azurerm_key_vault_secret can write the secrets through the data plane."
  type        = string
  default     = "Key Vault Secrets Officer"
}

variable "rbac_propagation_delay" {
  description = "How long to wait after assigning the deployer role on the Key Vault before writing the secrets (Azure role assignments take a while to propagate). deploy.sh passes 0s on the emulator."
  type        = string
  default     = "60s"
}

# -----------------------------------------------------------------------------
# App Service / Web App
# -----------------------------------------------------------------------------
variable "os_type" {
  description = "OS type for the App Service Plan."
  type        = string
  default     = "Linux"
}

variable "zone_balancing_enabled" {
  type    = bool
  default = false
}

variable "sku_name" {
  description = "App Service Plan SKU name."
  type        = string
  default     = "S1"
}

variable "dotnet_version" {
  description = "(Optional) Specifies the version of .NET to run. Possible values include 8.0, 9.0 and 10.0."
  type        = string
  default     = "10.0"

  validation {
    condition     = contains(["8.0", "9.0", "10.0"], var.dotnet_version)
    error_message = "The dotnet_version must be one of the supported versions: 8.0, 9.0, 10.0."
  }
}

variable "https_only" {
  type    = bool
  default = false
}

variable "minimum_tls_version" {
  type    = string
  default = "1.2"
}

variable "always_on" {
  type    = bool
  default = true
}

variable "http2_enabled" {
  type    = bool
  default = false
}

variable "public_network_access_enabled" {
  description = "Whether the Web App accepts requests from public networks."
  type        = bool
  default     = true
}

variable "vnet_route_all_enabled" {
  description = "Whether all outbound traffic of the Web App is routed into the virtual network (regional VNet integration), so that the private endpoints of the store, the vault and the server are used."
  type        = bool
  default     = true
}

variable "identity_type" {
  description = "Type of managed identity of the Web App. UserAssigned: the identity created by this configuration, which AZURE_CLIENT_ID selects in the app."
  type        = string
  default     = "UserAssigned"

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned"], var.identity_type)
    error_message = "The identity_type must be SystemAssigned or UserAssigned."
  }
}

variable "scm_do_build_during_deployment" {
  description = "Whether App Service builds the deployed zip with Oryx (SCM_DO_BUILD_DURING_DEPLOYMENT)."
  type        = bool
  default     = true
}

variable "enable_oryx_build" {
  description = "Whether the Oryx build runs for the deployed zip (ENABLE_ORYX_BUILD)."
  type        = bool
  default     = true
}

variable "login_name" {
  description = "Login name for the application (scopes activity ownership)."
  type        = string
  default     = "paolo"
}

variable "websites_port" {
  description = "Port the application listens on inside its container (WEBSITES_PORT)."
  type        = number
  default     = 8000
}

variable "log_analytics_sku" {
  description = "SKU of the Log Analytics workspace."
  type        = string
  default     = "PerGB2018"
}

variable "log_analytics_retention_in_days" {
  description = "Data retention of the Log Analytics workspace in days."
  type        = number
  default     = 30
}

variable "tags" {
  type = map(string)
  default = {
    environment = "test"
    iac         = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vnet_address_space" {
  type    = list(string)
  default = ["10.0.0.0/8"]
}

variable "webapp_subnet_name" {
  type    = string
  default = "app-subnet"
}

variable "webapp_subnet_address_prefix" {
  type    = list(string)
  default = ["10.0.0.0/24"]
}

variable "pe_subnet_name" {
  type    = string
  default = "pe-subnet"
}

variable "pe_subnet_address_prefix" {
  type    = list(string)
  default = ["10.0.1.0/24"]
}

variable "nat_gateway_sku_name" {
  type    = string
  default = "Standard"
}

variable "nat_gateway_idle_timeout_in_minutes" {
  type    = number
  default = 4
}

variable "nat_gateway_zones" {
  type    = list(string)
  default = ["1"]
}

variable "webapp_subnet_delegation" {
  description = "Service the Web App subnet is delegated to, required for regional VNet integration."
  type        = string
  default     = "Microsoft.Web/serverFarms"
}

variable "subnet_private_endpoint_network_policies" {
  description = "Private endpoint network policies of the subnets (Enabled, Disabled, NetworkSecurityGroupEnabled or RouteTableEnabled)."
  type        = string
  default     = "Enabled"
}

variable "subnet_private_link_service_network_policies_enabled" {
  description = "Whether private link service network policies are enabled on the subnets."
  type        = bool
  default     = false
}

variable "postgres_private_dns_zone_name" {
  description = "Private DNS zone of the PostgreSQL flexible server private endpoint."
  type        = string
  default     = "privatelink.postgres.database.azure.com"
}

variable "app_configuration_private_dns_zone_name" {
  description = "Private DNS zone of the App Configuration private endpoint."
  type        = string
  default     = "privatelink.azconfig.io"
}

variable "key_vault_private_dns_zone_name" {
  description = "Private DNS zone of the Key Vault private endpoint."
  type        = string
  default     = "privatelink.vaultcore.azure.net"
}

variable "private_dns_zone_group_name" {
  description = "Name of the private DNS zone group of every private endpoint, the same in the three provisioning variants."
  type        = string
  default     = "default"
}

variable "private_endpoint_is_manual_connection" {
  description = "Whether the private endpoint connections require manual approval by the resource owner."
  type        = bool
  default     = false
}

variable "postgres_private_endpoint_subresource_name" {
  description = "Sub-resource (group id) of the PostgreSQL flexible server private endpoint."
  type        = string
  default     = "postgresqlServer"
}

variable "app_configuration_private_endpoint_subresource_name" {
  description = "Sub-resource (group id) of the App Configuration store private endpoint."
  type        = string
  default     = "configurationStores"
}

variable "key_vault_private_endpoint_subresource_name" {
  description = "Sub-resource (group id) of the Key Vault private endpoint."
  type        = string
  default     = "vault"
}
