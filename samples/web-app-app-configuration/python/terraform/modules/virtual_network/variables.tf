variable "resource_group_name" {
  description = "Resource Group name"
  type        = string
}

variable "location" {
  description = "Location in which to deploy the network"
  type        = string
}

variable "vnet_name" {
  description = "VNET name"
  type        = string
}

variable "address_space" {
  description = "VNET address space"
  type        = list(string)
}

variable "subnets" {
  description = "Subnets configuration"
  type = list(object({
    name                                          = string
    address_prefixes                              = list(string)
    private_endpoint_network_policies             = string
    private_link_service_network_policies_enabled = bool
    delegation                                    = string
  }))
}

variable "tags" {
  description = "(Optional) Specifies the tags of the Azure Virtual Network resource."
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "Specifies the resource id of the Azure Log Analytics workspace."
  type        = string
}

variable "delegation_name" {
  description = "(Optional) Specifies the name of the delegation block created for a delegated subnet. Defaults to delegation."
  type        = string
  default     = "delegation"
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic setting of the virtual network. Defaults to DiagnosticsSettings."
  type        = string
  default     = "DiagnosticsSettings"
}

variable "log_categories" {
  description = "(Optional) Specifies the log categories the diagnostic setting enables."
  type        = list(string)
  default     = ["VMProtectionAlerts"]
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories the diagnostic setting enables. Defaults to none: many subscriptions carry an Azure Policy that already creates a diagnostic setting forwarding AllMetrics for every new virtual network, and Azure rejects a second setting for the same resource, category and sink with a 409 Conflict."
  type        = list(string)
  default     = []
}
