variable "prefix" {
  description = "(Optional) Specifies the prefix for the name of the Azure resources."
  type        = string
  default     = "websql"

  validation {
    condition     = var.prefix == null || length(var.prefix) >= 2
    error_message = "The prefix must be at least 2 characters long."
  }
}

variable "suffix" {
  description = "(Optional) Specifies the suffix for the name of the Azure resources."
  type        = string
  default     = "test"

  validation {
    condition     = var.suffix == null || length(var.suffix) >= 2
    error_message = "The suffix must be at least 2 characters long."
  }
}

variable "location" {
  description = "(Required) Specifies the location for all resources."
  type        = string
  default     = null
}

variable "administrator_login" {
  description = "(Required) Specifies the administrator login for the SQL server."
  type        = string
  default     = "sqladmin"
}

variable "administrator_login_password" {
  description = "(Required) Specifies the administrator login password for the SQL server."
  type        = string
  default     = "P@ssw0rd1234!"
}

variable "sql_version" {
  description = "(Optional) Specifies the version of the SQL server."
  type        = string
  default     = "12.0"
}

variable "public_network_access_enabled" {
  description = "(Optional) Specifies whether the public network access is enabled or disabled for the SQL server."
  type        = bool
  default     = true
}

variable "outbound_network_restriction_enabled" {
  description = "(Optional) Specifies whether to restrict outbound network access for the SQL server."
  type        = bool
  default     = false
}

variable "start_ip_address" {
  description = "(Required) The starting IP address to allow through the firewall for this rule."
  type        = string
  default     = "0.0.0.0"
}

variable "end_ip_address" {
  description = "(Required) The ending IP address to allow through the firewall for this rule."
  type        = string
  default     = "255.255.255.255"
}

variable "sql_database_name" {
  description = "(Optional) Specifies the name of the SQL database."
  type        = string
  default     = "PlannerDB"
}

variable "sku" {
  description = "Specifies the SKU for the database."
  type = object({
    name     = string
    tier     = string
    capacity = number
  })
  default = {
    name     = "S0"
    tier     = "Standard"
    capacity = 10
  }
}

variable "auto_pause_delay" {
  description = "Time in minutes after which database is automatically paused. A value of -1 means that automatic pause is disabled."
  type        = number
  default     = -1
}

variable "availability_zone" {
  description = "Specifies the availability zone. Valid values are 1, 2, 3, or -1 for no preference."
  type        = number
  default     = -1
  validation {
    condition     = contains([-1, 1, 2, 3], var.availability_zone)
    error_message = "Availability zone must be -1, 1, 2, or 3."
  }
}

variable "catalog_collation" {
  description = "Specifies the collation of the metadata catalog."
  type        = string
  default     = "DATABASE_DEFAULT"
}

variable "collation" {
  description = "Specifies the collation of the database."
  type        = string
  default     = "SQL_Latin1_General_CP1_CI_AS"
}

variable "create_mode" {
  description = "The create mode of the database."
  type        = string
  default     = "Default"
  validation {
    condition = contains([
      "Default",
      "Copy",
      "OnlineSecondary",
      "PointInTimeRestore",
      "Recovery",
      "Restore",
      "RestoreExternalBackup",
      "RestoreExternalBackupSecondary",
      "RestoreLongTermRetentionBackup",
      "Secondary"
    ], var.create_mode)
    error_message = "Invalid create mode specified."
  }
}

variable "elastic_pool_resource_id" {
  description = "The ID of the elastic pool containing this database."
  type        = string
  default     = null
}

variable "high_availability_replica_count" {
  description = "The number of readonly secondary replicas associated with the database."
  type        = number
  default     = 0
}

variable "is_ledger_on" {
  description = "Whether or not this database is a ledger database."
  type        = bool
  default     = false
}

variable "license_type" {
  description = "Specifies the license type to apply for this database."
  type        = string
  default     = null
  validation {
    condition     = var.license_type == null || try(contains(["LicenseIncluded", "BasePrice"], var.license_type), false)
    error_message = "License type must be 'LicenseIncluded' or 'BasePrice'."
  }
}

variable "min_capacity" {
  description = "Minimal capacity that database will always have allocated."
  type        = string
  default     = "0"
}

variable "read_scale" {
  description = "If enabled, connections that have application intent set to readonly can be routed to a readonly secondary replica."
  type        = string
  default     = "Disabled"
  validation {
    condition     = contains(["Enabled", "Disabled"], var.read_scale)
    error_message = "Read scale must be 'Enabled' or 'Disabled'."
  }
}

variable "sql_database_zone_redundant" {
  description = "Whether or not this database is zone redundant."
  type        = bool
  default     = false
}

variable "max_size_gb" {
  description = "The max size of the database in gigabytes."
  type        = number
  default     = null
}

variable "sql_database_username" {
  description = "(Required) The administrator username of the SQL Server (set at server level)."
  type        = string
  default     = "testuser"
  sensitive   = true
}

variable "sql_database_password" {
  description = "(Required) The administrator password of the SQL Server (set at server level)."
  type        = string
  default     = "TestP@ssw0rd123"
  sensitive   = true
}

variable "os_type" {
  description = "(Required) Specifies the O/S type for the App Services to be hosted in this plan. Possible values include Windows, Linux, and WindowsContainer. Changing this forces a new resource to be created."
  type        = string
  default     = "Linux"

  validation {
    condition = contains([
      "Windows",
      "Linux",
      "WindowsContainer"
    ], var.os_type)
    error_message = "The os_type must be either 'Windows', 'Linux', or 'WindowsContainer'."
  }
}

variable "zone_balancing_enabled" {
  description = "(Optional) Should the Service Plan balance across Availability Zones in the region."
  type        = bool
  default     = false
}

variable "sku_tier" {
  description = "(Optional) Specifies the tier name for the hosting plan."
  type        = string
  default     = "Standard"

  validation {
    condition = contains([
      "Basic",
      "Standard",
      "ElasticPremium",
      "Premium",
      "PremiumV2",
      "Premium0V3",
      "PremiumV3",
      "PremiumMV3",
      "Isolated",
      "IsolatedV2",
      "WorkflowStandard",
      "FlexConsumption"
    ], var.sku_tier)
    error_message = "The sku_tier must be one of the allowed values."
  }
}
variable "sku_name" {
  description = "(Optional) Specifies the SKU name for the hosting plan."
  type        = string
  default     = "S1"

  validation {
    condition = contains([
      "B1", "B2", "B3",
      "S1", "S2", "S3",
      "EP1", "EP2", "EP3",
      "P1", "P2", "P3",
      "P1V2", "P2V2", "P3V2",
      "P0V3", "P1V3", "P2V3", "P3V3",
      "P1MV3", "P2MV3", "P3MV3", "P4MV3", "P5MV3",
      "I1", "I2", "I3",
      "I1V2", "I2V2", "I3V2", "I4V2", "I5V2", "I6V2",
      "WS1", "WS2", "WS3",
      "FC1"
    ], var.sku_name)
    error_message = "The sku_name must be one of the allowed values."
  }
}

variable "python_version" {
  description = "(Optional) Specifies the version of Python to run. Possible values include 3.12, 3.11, 3.10, 3.9, 3.8 and 3.7."
  type        = string
  default     = "3.12"

  validation {
    condition = contains([
      "3.12",
      "3.11",
      "3.10",
      "3.9",
      "3.8",
      "3.7"
    ], var.python_version)
    error_message = "The python_version must be one of the supported versions: 3.13, 3.12, 3.11, 3.10, 3.9, 3.8, 3.7."
  }
}

variable "https_only" {
  description = "(Optional) Specifies whether the Linux Web App require HTTPS connections. Defaults to false."
  type        = bool
  default     = false
}

variable "minimum_tls_version" {
  description = "(Optional) Specifies the minimum version of TLS required for SSL requests. Possible values include: 1.0, 1.1, 1.2 and 1.3. Defaults to 1.2."
  type        = string
  default     = "1.2"

  validation {
    condition = contains([
      "1.0",
      "1.1",
      "1.2",
      "1.3"
    ], var.minimum_tls_version)
    error_message = "The minimum_tls_version must be one of the allowed values."
  }
}

variable "always_on" {
  description = "(Optional) Specifies whether the Linux Web App is Always On enabled. Defaults to true."
  type        = bool
  default     = true
}

variable "http2_enabled" {
  description = "(Optional) Specifies whether HTTP/2 is enabled for the Linux Web App."
  type        = bool
  default     = false
}

variable "webapp_public_network_access_enabled" {
  description = "(Optional) Specifies whether the public network access is enabled or disabled."
  type        = bool
  default     = true
}

variable "repo_url" {
  description = "(Optional) Specifies the Git repository URL."
  type        = string
  default     = ""

  validation {
    condition     = var.repo_url == "" || can(regex("^https?://", var.repo_url))
    error_message = "The repo_url must be empty or a valid HTTP/HTTPS URL."
  }
}

variable "login_name" {
  description = "(Required) Specifies the login name for the application."
  type        = string
  default     = "paolo"
}

variable "secret_name" {
  description = "(Optional) Specifies the name of the Key Vault secret for the SQL connection string."
  type        = string
  default     = "sql-connection-string"
}

variable "cert_name" {
  description = "(Optional) Specifies the name of the Key Vault certificate."
  type        = string
  default     = "webapp-cert"
}

variable "cert_subject" {
  description = "(Optional) Specifies the subject of the self-signed certificate."
  type        = string
  default     = "sample-web-app-sql"
}

variable "tags" {
  description = "(Optional) Specifies the tags to be applied to the resources."
  type        = map(string)
  default = {
    environment = "test"
    iac         = "terraform"
  }
}