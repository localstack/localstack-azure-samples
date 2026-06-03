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
  description = "Suffix for the name of the Azure resources."
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
# MySQL flexible server
# -----------------------------------------------------------------------------
variable "mysql_admin_login" {
  description = "Administrator login for the MySQL flexible server."
  type        = string
  default     = "myadmin"
}

variable "mysql_admin_password" {
  description = "Administrator password for the MySQL flexible server. Pass via -var or the MYSQL_ADMIN_PASSWORD env var; do NOT commit."
  type        = string
  sensitive   = true
  default     = "P@ssw0rd1234!"
}

variable "mysql_version" {
  description = "MySQL major version."
  type        = string
  default     = "8.0.21"

  validation {
    condition     = contains(["5.7", "8.0.21"], var.mysql_version)
    error_message = "The mysql_version must be one of: 5.7, 8.0.21."
  }
}

variable "mysql_sku_name" {
  description = "Compute SKU for the MySQL flexible server (e.g. B_Standard_B1ms)."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "mysql_storage_size_gb" {
  description = "Storage size in GB for the MySQL flexible server."
  type        = number
  default     = 32
}

variable "mysql_backup_retention_days" {
  description = "Backup retention period in days for the MySQL flexible server."
  type        = number
  default     = 7
}

variable "mysql_database_name" {
  description = "Name of the application database to create on the MySQL flexible server."
  type        = string
  default     = "PlannerDB"
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
  default     = "3.12"

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

variable "repo_url" {
  type    = string
  default = ""

  validation {
    condition     = var.repo_url == "" || can(regex("^https?://", var.repo_url))
    error_message = "The repo_url must be empty or a valid HTTP/HTTPS URL."
  }
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
