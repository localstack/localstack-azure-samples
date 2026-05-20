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

variable "python_version" {
  description = "(Optional) Specifies the version of Python to run."
  type        = string
  default     = "3.12"
}

variable "app_settings" {
  description = "(Optional) A map of key-value pairs for App Settings."
  type        = map(string)
  default     = {}
}

variable "repo_url" {
  description = "(Optional) Specifies the Git repository URL."
  type        = string
  default     = ""
}

variable "repo_branch" {
  description = "(Optional) Specifies the Git repository branch."
  type        = string
  default     = "main"
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
