variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location for the Web App."
  type        = string
}

variable "name" {
  description = "(Required) Specifies the name of the Web App."
  type        = string
}

variable "service_plan_id" {
  description = "(Required) Specifies the ID of the App Service Plan within which to create this Web App."
  type        = string
}

variable "https_only" {
  description = "(Optional) Specifies whether the Web App requires HTTPS connections."
  type        = bool
  default     = false
}

variable "virtual_network_subnet_id" {
  description = "(Optional) The subnet id which will be used by this Web App for regional virtual network integration."
  type        = string
  default     = null
}

variable "vnet_route_all_enabled" {
  description = "(Optional) Specifies whether to route all traffic from the Web App into the virtual network. This is only applicable if virtual_network_subnet_id is specified. Defaults to false."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "(Optional) Specifies whether the public network access is enabled or disabled."
  type        = bool
  default     = true
}

variable "always_on" {
  description = "(Optional) Specifies whether the Web App is Always On enabled."
  type        = bool
  default     = true
}

variable "http2_enabled" {
  description = "(Optional) Specifies whether HTTP/2 is enabled for the Web App."
  type        = bool
  default     = false
}

variable "minimum_tls_version" {
  description = "(Optional) Specifies the minimum version of TLS required for SSL requests."
  type        = string
  default     = "1.2"
}

variable "dotnet_version" {
  description = "(Optional) Specifies the version of .NET to run. Possible values include 8.0, 9.0 and 10.0."
  type        = string
  default     = "10.0"

  validation {
    condition     = contains(["8.0", "9.0", "10.0"], var.dotnet_version)
    error_message = "The dotnet_version must be one of the supported versions: 8.0, 9.0, 10.0."
  }
}

variable "app_settings" {
  description = "(Optional) A map of key-value pairs for App Settings."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "(Optional) Specifies the tags to be applied to the resources."
  type        = map(any)
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "Specifies the resource id of the Azure Log Analytics workspace."
  type        = string
}
