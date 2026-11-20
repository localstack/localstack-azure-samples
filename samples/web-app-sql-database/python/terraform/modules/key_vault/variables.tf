variable "name" {
  description = "(Required) Specifies the name of the Key Vault."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the Key Vault."
  type        = string
}

variable "tenant_id" {
  description = "(Required) Specifies the Microsoft Entra tenant id of the Key Vault and of its access policies."
  type        = string
}

variable "sku_name" {
  description = "(Optional) Specifies the SKU name of the Key Vault: standard or premium."
  type        = string
  default     = "standard"
}

variable "soft_delete_retention_days" {
  description = "(Optional) Specifies the number of days a deleted vault is retained."
  type        = number
  default     = 7
}

variable "purge_protection_enabled" {
  description = "(Optional) Specifies whether purge protection is enabled. Azure SQL requires it on the vault of a TDE protector key."
  type        = bool
  default     = true
}

variable "deployer_object_id" {
  description = "(Required) Specifies the object id of the identity running Terraform, which creates the key, the secret and the certificate."
  type        = string
}

variable "sql_server_identity_principal_id" {
  description = "(Required) Specifies the principal id of the user-assigned managed identity the SQL server reads its TDE protector key with."
  type        = string
}

variable "tde_key_name" {
  description = "(Required) Specifies the name of the key used as the TDE protector of the SQL server."
  type        = string
}

variable "secret_name" {
  description = "(Required) Specifies the name of the secret that holds the SQL connection string."
  type        = string
}

variable "sql_server_fqdn" {
  description = "(Required) Specifies the fully qualified domain name of the SQL server."
  type        = string
}

variable "sql_database_name" {
  description = "(Required) Specifies the name of the SQL database."
  type        = string
}

variable "sql_database_username" {
  description = "(Required) Specifies the username of the SQL database user the app connects as."
  type        = string
}

variable "sql_database_password" {
  description = "(Required) Specifies the password of the SQL database user the app connects as."
  type        = string
  sensitive   = true
}

variable "cert_name" {
  description = "(Required) Specifies the name of the certificate the web app serves HTTPS with on port 8443."
  type        = string
}

variable "cert_subject" {
  description = "(Required) Specifies the common name of the certificate's subject."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace the diagnostic setting sends to."
  type        = string
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic setting."
  type        = string
  default     = "default"
}

variable "log_categories" {
  description = "(Optional) Specifies the log categories the diagnostic setting enables."
  type        = list(string)
  default     = ["AuditEvent", "AzurePolicyEvaluationDetails"]
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories the diagnostic setting enables."
  type        = list(string)
  default     = ["AllMetrics"]
}

variable "log_analytics_destination_type" {
  description = "(Optional) Specifies where the diagnostic setting writes the logs in the workspace: Dedicated writes each category to its resource-specific table (AZKVAuditLogs, AZKVPolicyEvaluationDetailsLogs), AzureDiagnostics to the shared AzureDiagnostics table."
  type        = string
  default     = "Dedicated"

  validation {
    condition     = contains(["AzureDiagnostics", "Dedicated"], var.log_analytics_destination_type)
    error_message = "The log_analytics_destination_type must be AzureDiagnostics or Dedicated."
  }
}

variable "tags" {
  description = "(Optional) Specifies the tags of the resources."
  type        = map(string)
  default     = {}
}
