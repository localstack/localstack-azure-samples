variable "name" {
  description = "(Required) Specifies the name of the PostgreSQL flexible server. Changing this forces a new resource to be created."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group of the PostgreSQL flexible server."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location where the PostgreSQL flexible server is deployed."
  type        = string
}

variable "administrator_login" {
  description = "(Required) Specifies the administrator login of the PostgreSQL flexible server."
  type        = string
}

variable "administrator_password" {
  description = "(Required) Specifies the administrator password of the PostgreSQL flexible server."
  type        = string
  sensitive   = true
}

variable "postgresql_version" {
  description = "(Optional) Specifies the PostgreSQL major version. Defaults to 16."
  type        = string
  default     = "16"
}

variable "sku_name" {
  description = "(Optional) Specifies the compute SKU of the server, in the tier_name form the provider expects (for example B_Standard_B1ms). Defaults to B_Standard_B1ms."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "(Optional) Specifies the storage size of the server in MB. Defaults to 32768."
  type        = number
  default     = 32768
}

variable "backup_retention_days" {
  description = "(Optional) Specifies the backup retention period in days. Defaults to 7."
  type        = number
  default     = 7
}

variable "geo_redundant_backup_enabled" {
  description = "(Optional) Specifies whether geo-redundant backup is enabled. Defaults to false."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "(Optional) Specifies whether the server accepts connections from public networks. Defaults to true, so the deploy machine can reach the server through the firewall rule for the post-deploy psql bootstrap; the Web App reaches the server through its private endpoint."
  type        = bool
  default     = true
}

variable "database_name" {
  description = "(Optional) Specifies the name of the application database created on the server. Defaults to PlannerDB."
  type        = string
  default     = "PlannerDB"
}

variable "database_charset" {
  description = "(Optional) Specifies the charset of the application database. Defaults to UTF8."
  type        = string
  default     = "UTF8"
}

variable "database_collation" {
  description = "(Optional) Specifies the collation of the application database. Defaults to en_US.utf8."
  type        = string
  default     = "en_US.utf8"
}

variable "firewall_rule_name" {
  description = "(Optional) Specifies the name of the server-level firewall rule that lets the deploy machine run the psql bootstrap. Defaults to AllowAllIPs."
  type        = string
  default     = "AllowAllIPs"
}

variable "firewall_start_ip" {
  description = "(Optional) Specifies the first address of the firewall rule range. Defaults to 0.0.0.0, which together with the default end address allows every address, appropriate for a sample only."
  type        = string
  default     = "0.0.0.0"
}

variable "firewall_end_ip" {
  description = "(Optional) Specifies the last address of the firewall rule range. Defaults to 255.255.255.255."
  type        = string
  default     = "255.255.255.255"
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace the diagnostic settings send logs and metrics to."
  type        = string
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic setting of the server. Defaults to DiagnosticsSettings."
  type        = string
  default     = "DiagnosticsSettings"
}

variable "log_categories" {
  description = "(Optional) Specifies the log categories the diagnostic setting enables."
  type        = list(string)
  default     = ["PostgreSQLLogs"]
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories the diagnostic setting enables."
  type        = list(string)
  default     = ["AllMetrics"]
}

variable "tags" {
  description = "(Optional) Specifies the tags of the PostgreSQL flexible server."
  type        = map(string)
  default     = {}
}
