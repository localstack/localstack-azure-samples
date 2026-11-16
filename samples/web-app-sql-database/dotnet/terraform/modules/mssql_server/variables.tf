variable "name" {
  description = "(Required) Specifies the name of the SQL server."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the SQL server."
  type        = string
}

variable "administrator_login" {
  description = "(Required) Specifies the administrator login of the SQL server."
  type        = string
}

variable "administrator_login_password" {
  description = "(Required) Specifies the administrator login password of the SQL server."
  type        = string
  sensitive   = true
}

variable "minimum_tls_version" {
  description = "(Optional) Specifies the minimum TLS version of the SQL server."
  type        = string
  default     = "1.2"
}

variable "public_network_access_enabled" {
  description = "(Optional) Specifies whether public network access is allowed for the SQL server."
  type        = bool
  default     = true
}

variable "outbound_network_restriction_enabled" {
  description = "(Optional) Specifies whether outbound network traffic is restricted for the SQL server."
  type        = bool
  default     = false
}

variable "sql_version" {
  description = "(Optional) Specifies the version of the SQL server."
  type        = string
  default     = "12.0"
}

variable "managed_identity_id" {
  description = "(Required) Specifies the resource id of the user-assigned managed identity the server reads its TDE protector key with."
  type        = string
}

variable "firewall_rule_name" {
  description = "(Optional) Specifies the name of the firewall rule."
  type        = string
  default     = "AllowAllIPs"
}

variable "start_ip_address" {
  description = "(Optional) Specifies the start IP address of the firewall rule."
  type        = string
  default     = "0.0.0.0"
}

variable "end_ip_address" {
  description = "(Optional) Specifies the end IP address of the firewall rule."
  type        = string
  default     = "255.255.255.255"
}

variable "database_name" {
  description = "(Required) Specifies the name of the SQL database."
  type        = string
}

variable "sku_name" {
  description = "(Optional) Specifies the SKU name of the SQL database."
  type        = string
  default     = "S0"
}

variable "auto_pause_delay" {
  description = "(Optional) Specifies the time in minutes after which the database automatically pauses. A value of -1 disables automatic pausing."
  type        = number
  default     = -1
}

variable "collation" {
  description = "(Optional) Specifies the collation of the SQL database."
  type        = string
  default     = "SQL_Latin1_General_CP1_CI_AS"
}

variable "create_mode" {
  description = "(Optional) Specifies the mode used for database creation."
  type        = string
  default     = "Default"
}

variable "elastic_pool_id" {
  description = "(Optional) Specifies the resource id of the elastic pool containing the database."
  type        = string
  default     = null
}

variable "max_size_gb" {
  description = "(Optional) Specifies the maximum size of the database in gigabytes."
  type        = number
  default     = null
}

variable "min_capacity" {
  description = "(Optional) Specifies the minimal capacity that the database will always have allocated."
  type        = number
  default     = null
}

variable "read_replica_count" {
  description = "(Optional) Specifies the number of readonly secondary replicas associated with the database."
  type        = number
  default     = 0
}

variable "read_scale" {
  description = "(Optional) Specifies whether read-only connections are routed to a secondary replica."
  type        = bool
  default     = false
}

variable "zone_redundant" {
  description = "(Optional) Specifies whether the database is zone redundant."
  type        = bool
  default     = false
}

variable "license_type" {
  description = "(Optional) Specifies the license type to apply for the database."
  type        = string
  default     = null
}

variable "ledger_enabled" {
  description = "(Optional) Specifies whether the database is a ledger database."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace the diagnostic setting of the database sends to."
  type        = string
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic setting of the database."
  type        = string
  default     = "default"
}

variable "log_categories" {
  description = "(Optional) Specifies the log categories of the database the diagnostic setting enables. SQLSecurityAuditEvents carries the records of the database's auditing policy, which sends to Azure Monitor."
  type        = list(string)
  default = [
    "SQLInsights",
    "AutomaticTuning",
    "QueryStoreRuntimeStatistics",
    "QueryStoreWaitStatistics",
    "Errors",
    "DatabaseWaitStatistics",
    "Timeouts",
    "Blocks",
    "Deadlocks",
    "SQLSecurityAuditEvents",
  ]
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories of the database the diagnostic setting enables: every one a database has. WorkloadManagement groups the metrics of dedicated SQL pools, so a database of this sample exports none of them."
  type        = list(string)
  default     = ["Basic", "InstanceAndAppAdvanced", "WorkloadManagement"]
}

variable "tags" {
  description = "(Optional) Specifies the tags of the resources."
  type        = map(string)
  default     = {}
}
