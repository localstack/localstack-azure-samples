variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the Azure Log Analytics workspace"
  type        = string
}

variable "name" {
  description = "(Required) Specifies the name of the Azure Log Analytics workspace"
  type        = string
}

variable "sku" {
  description = "(Optional) Specifies the sku of the Azure Log Analytics workspace"
  type        = string
  default     = "PerGB2018"

  validation {
    condition     = contains(["Free", "Standalone", "PerNode", "PerGB2018"], var.sku)
    error_message = "The log analytics sku is incorrect."
  }
}

variable "retention_in_days" {
  description = " (Optional) Specifies the workspace data retention in days. Possible values are either 7 (Free Tier only) or range between 30 and 730."
  type        = number
  default     = 30
}

variable "tags" {
  description = "(Optional) Specifies the tags of the Azure Log Analytics workspace."
  type        = map(any)
  default     = {}
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic setting of the workspace."
  type        = string
  default     = "default"
}

variable "log_categories" {
  description = "(Optional) Specifies the log categories that the diagnostic setting of the workspace sends to the workspace itself. Audit records the queries run on the workspace in the LAQueryLogs table."
  type        = list(string)
  default     = ["Audit"]
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories that the diagnostic setting of the workspace sends to the workspace itself."
  type        = list(string)
  default     = ["AllMetrics"]
}
