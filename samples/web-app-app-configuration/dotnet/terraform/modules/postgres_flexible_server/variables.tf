variable "name" {
  description = "Name of the PostgreSQL flexible server."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "administrator_login" {
  type = string
}

variable "administrator_password" {
  type      = string
  sensitive = true
}

variable "postgresql_version" {
  type    = string
  default = "16"
}

variable "sku_name" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "storage_mb" {
  type    = number
  default = 32768
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "database_name" {
  type    = string
  default = "PlannerDB"
}

variable "database_charset" {
  type    = string
  default = "UTF8"
}

variable "database_collation" {
  type    = string
  default = "en_US.utf8"
}

variable "firewall_rule_name" {
  description = "Server-level firewall rule that allows the deploy machine to run the psql bootstrap."
  type        = string
  default     = "AllowAllIPs"
}

variable "firewall_start_ip" {
  type    = string
  default = "0.0.0.0"
}

variable "firewall_end_ip" {
  type    = string
  default = "255.255.255.255"
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
