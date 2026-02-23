variable "location" {
  description = "(Required) Specifies the location for all resources."
  type        = string
  default     = "westeurope"
}

variable "administrator_login" {
  description = "(Required) Specifies the administrator login for the PostgreSQL Flexible Server."
  type        = string
  default     = "pgadmin"
}

variable "administrator_password" {
  description = "(Required) Specifies the administrator login password for the PostgreSQL Flexible Server."
  type        = string
  default     = "P@ssw0rd12345!"
  sensitive   = true
}

variable "postgresql_version" {
  description = "(Optional) Specifies the version of PostgreSQL to deploy."
  type        = string
  default     = "16"

  validation {
    condition     = contains(["13", "14", "15", "16"], var.postgresql_version)
    error_message = "The postgresql_version must be one of: 13, 14, 15, 16."
  }
}

variable "sku_name" {
  description = "(Optional) Specifies the SKU name for the PostgreSQL Flexible Server."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "(Optional) Specifies the storage size in MB for the PostgreSQL Flexible Server."
  type        = number
  default     = 32768
}

variable "backup_retention_days" {
  description = "(Optional) Specifies the number of days to retain backups."
  type        = number
  default     = 7
}

variable "geo_redundant_backup_enabled" {
  description = "(Optional) Specifies whether geo-redundant backup is enabled."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "(Optional) Specifies whether public network access is enabled."
  type        = bool
  default     = true
}

variable "primary_database_name" {
  description = "(Optional) Specifies the name of the primary database."
  type        = string
  default     = "sampledb"
}

variable "secondary_database_name" {
  description = "(Optional) Specifies the name of the secondary (analytics) database."
  type        = string
  default     = "analyticsdb"
}

variable "tags" {
  description = "(Optional) Specifies the tags to be applied to the resources."
  type        = map(string)
  default = {
    environment = "test"
    iac         = "terraform"
  }
}
