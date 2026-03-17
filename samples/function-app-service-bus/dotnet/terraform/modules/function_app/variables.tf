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

variable "storage_account_name" {
  description = "(Required) Specifies the name of the storage account used by the Function App."
  type        = string
}

variable "storage_account_access_key" {
  description = "(Required) Specifies the primary access key of the storage account used by the Function App."
  type        = string
  sensitive   = true
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

variable "use_dotnet_isolated_runtime" {
  description = "(Optional) Should the DotNet process use an isolated runtime. Defaults to false."
  type        = bool
  default     = true
}

variable "java_version" {
  description = "(Optional) The Version of Java to use."
  type        = string
  default     = null
}

variable "node_version" {
  description = "(Optional) The version of Node.js to run."
  type        = string
  default     = null
}

variable "dotnet_version" {
  description = "(Optional) The version of .NET to use."
  type        = string
  default     = null
}

variable "python_version" {
  description = "(Optional) The version of Python to run."
  type        = string
  default     = null
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

variable "managed_identity_type" {
  description = "(Optional) Specifies the type of managed identity."
  type        = string
  default     = "UserAssigned"

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned"], var.managed_identity_type)
    error_message = "The managed identity type must be either SystemAssigned or UserAssigned."
  }
}

variable "managed_identity_id" {
  description = "(Optional) Specifies the resource id of the user-assigned managed identity."
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Specifies the resource id of the Azure Log Analytics workspace."
  type        = string
}
