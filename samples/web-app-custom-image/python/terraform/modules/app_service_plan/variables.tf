variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location for the App Service Plan."
  type        = string
}

variable "name" {
  description = "(Required) Specifies the name of the App Service Plan."
  type        = string
}

variable "sku_name" {
  description = "(Required) Specifies the SKU name for the App Service Plan."
  type        = string
}

variable "os_type" {
  description = "(Required) Specifies the O/S type for the App Services to be hosted in this plan."
  type        = string
  default     = "Linux"
}

variable "zone_balancing_enabled" {
  description = "(Optional) Should the Service Plan balance across Availability Zones in the region."
  type        = bool
  default     = false
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