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

variable "rbac_propagation_delay" {
  description = "How long to wait after assigning Key Vault Secrets Officer to the deploying principal before writing the secrets (Azure role assignments take a while to propagate). deploy.sh passes 0s on the emulator."
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

variable "python_version" {
  description = "Python runtime version for the Web App."
  type        = string
  default     = "3.13"

  validation {
    condition     = contains(["3.13", "3.12", "3.11", "3.10", "3.9", "3.8", "3.7"], var.python_version)
    error_message = "Unsupported python_version."
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
  type    = bool
  default = true
}

variable "login_name" {
  description = "Login name for the application (scopes activity ownership)."
  type        = string
  default     = "paolo"
}

variable "websites_port" {
  type    = number
  default = 8000
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
