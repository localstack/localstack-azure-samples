variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the Web App."
  type        = string
}

variable "name" {
  description = "(Required) Specifies the globally unique name of the Web App."
  type        = string
}

variable "service_plan_id" {
  description = "(Required) Specifies the resource id of the App Service Plan that hosts the Web App."
  type        = string
}

variable "https_only" {
  description = "(Optional) Specifies whether the Web App requires HTTPS connections."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "(Optional) Specifies whether the public network access is enabled."
  type        = bool
  default     = true
}

variable "client_affinity_enabled" {
  description = "(Optional) Specifies whether client affinity (ARR affinity) is enabled."
  type        = bool
  default     = false
}

variable "always_on" {
  description = "(Optional) Specifies whether the Web App is always on."
  type        = bool
  default     = true
}

variable "http2_enabled" {
  description = "(Optional) Specifies whether HTTP/2 is enabled."
  type        = bool
  default     = false
}

variable "minimum_tls_version" {
  description = "(Optional) Specifies the minimum TLS version of the Web App."
  type        = string
  default     = "1.2"
}

variable "python_version" {
  description = "(Optional) Specifies the Python version of the Web App. Set either python_version or dotnet_version."
  type        = string
  default     = null
}

variable "dotnet_version" {
  description = "(Optional) Specifies the .NET version of the Web App. Set either python_version or dotnet_version."
  type        = string
  default     = null
}

variable "identity_type" {
  description = "(Optional) Specifies the type of managed identity of the Web App: SystemAssigned or UserAssigned."
  type        = string
  default     = "SystemAssigned"

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned"], var.identity_type)
    error_message = "The identity_type must be either SystemAssigned or UserAssigned."
  }
}

variable "identity_ids" {
  description = "(Optional) Specifies the resource ids of the user-assigned managed identities of the Web App. Used only when identity_type is UserAssigned."
  type        = list(string)
  default     = []
}

variable "app_settings" {
  description = "(Optional) Specifies the app settings of the Web App."
  type        = map(string)
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace."
  type        = string
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic setting of the Web App."
  type        = string
  default     = "default"
}

variable "log_categories" {
  description = "(Optional) Specifies the log categories that the diagnostic setting of the Web App sends to the Log Analytics workspace."
  type        = list(string)
  default = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServiceAuditLogs",
    "AppServiceIPSecAuditLogs",
    "AppServicePlatformLogs",
    "AppServiceAuthenticationLogs",
  ]
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories that the diagnostic setting of the Web App sends to the Log Analytics workspace."
  type        = list(string)
  default     = ["AllMetrics"]
}

variable "tags" {
  description = "(Optional) Specifies the tags of the Web App."
  type        = map(any)
  default     = {}
}
