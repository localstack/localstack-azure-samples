variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the Function App."
  type        = string
}

variable "name" {
  description = "(Required) Specifies the globally unique name of the Function App."
  type        = string
}

variable "service_plan_id" {
  description = "(Required) Specifies the resource id of the App Service Plan that hosts the Function App."
  type        = string
}

variable "storage_account_name" {
  description = "(Required) Specifies the name of the storage account that the Functions host uses for its own data (AzureWebJobsStorage)."
  type        = string
}

variable "storage_account_access_key" {
  description = "(Required) Specifies the access key of the storage account that the Functions host uses for its own data."
  type        = string
  sensitive   = true
}

variable "https_only" {
  description = "(Optional) Specifies whether the Function App requires HTTPS connections."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "(Optional) Specifies whether the public network access is enabled."
  type        = bool
  default     = true
}

variable "always_on" {
  description = "(Optional) Specifies whether the Function App is always on. The functions with triggers other than HTTP need it on a dedicated App Service plan."
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "(Optional) Specifies the minimum TLS version of the Function App."
  type        = string
  default     = "1.2"
}

variable "application_insights_connection_string" {
  description = "(Optional) Specifies the connection string of the Application Insights resource the Function App sends its telemetry to (APPLICATIONINSIGHTS_CONNECTION_STRING)."
  type        = string
  default     = null
  sensitive   = true
}

variable "python_version" {
  description = "(Optional) Specifies the Python version of the Function App. Set either python_version or dotnet_version."
  type        = string
  default     = null
}

variable "dotnet_version" {
  description = "(Optional) Specifies the .NET version of the Function App, which runs in the isolated worker model. Set either python_version or dotnet_version."
  type        = string
  default     = null
}

variable "identity_type" {
  description = "(Optional) Specifies the type of managed identity of the Function App: SystemAssigned or UserAssigned."
  type        = string
  default     = "SystemAssigned"

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned"], var.identity_type)
    error_message = "The identity_type must be either SystemAssigned or UserAssigned."
  }
}

variable "identity_ids" {
  description = "(Optional) Specifies the resource ids of the user-assigned managed identities of the Function App. Used only when identity_type is UserAssigned."
  type        = list(string)
  default     = []
}

variable "app_settings" {
  description = "(Optional) Specifies the app settings of the Function App."
  type        = map(string)
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace."
  type        = string
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic setting of the Function App."
  type        = string
  default     = "default"
}

variable "log_categories" {
  description = "(Optional) Specifies the log categories that the diagnostic setting of the Function App sends to the Log Analytics workspace."
  type        = list(string)
  default     = ["FunctionAppLogs"]
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories that the diagnostic setting of the Function App sends to the Log Analytics workspace."
  type        = list(string)
  default     = ["AllMetrics"]
}

variable "tags" {
  description = "(Optional) Specifies the tags of the Function App."
  type        = map(any)
  default     = {}
}
