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

variable "image_name" {
  description = "(Required) Specifies the name of the container image to deploy to the Web App."
  type        = string
  default     = "custom-image-webapp"
}

variable "image_tag" {
  description = "(Required) Specifies the tag of the container image to deploy to the Web App."
  type        = string
  default     = "v1"
}

variable "docker_registry_url" {
  description = "(Optional) Specifies the URL of the Docker registry where the container image is stored. This is required if the container image is stored in a private registry."
  type        = string
  default     = null
}

variable "managed_identity_id" {
  description = "(Optional) Specifies the ID of the user-assigned managed identity to be assigned to the Web App."
  type        = string
  default     = null
}

variable "docker_registry_username" {
  description = "Specifies the username of the Docker registry. This is required if the container image is stored in a private registry."
  type        = string
  default     = null
}

variable "docker_registry_password" {
  description = "Specifies the password of the Docker registry. This is required if the container image is stored in a private registry."
  type        = string
  default     = null
}