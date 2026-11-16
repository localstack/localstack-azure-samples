variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the Azure NAT Gateway"
  type        = string
}

variable "name" {
  description = "(Required) Specifies the name of the Azure NAT Gateway"
  type        = string
}

variable "tags" {
  description = "(Optional) Specifies the tags of the Azure NAT Gateway"
  type        = map(any)
  default     = {}
}

variable "sku_name" {
  description = "(Optional) The SKU which should be used. At this time the only supported value is Standard. Defaults to Standard"
  type        = string
  default     = "Standard"
}

variable "idle_timeout_in_minutes" {
  description = "(Optional) The idle timeout which should be used in minutes. Defaults to 4."
  type        = number
  default     = 4
}

variable "zones" {
  description = " (Optional) A list of Availability Zones in which this NAT Gateway should be located. Changing this forces a new NAT Gateway to be created."
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "(Required) A map of subnet ids to associate with the NAT Gateway"
  type        = map(string)
}

variable "public_ip_prefix_name" {
  description = "(Required) The name of the public IP prefix to create and associate with the NAT Gateway."
  type        = string
  default     = null
}

variable "public_ip_prefix_length" {
  description = "(Required) The length of the public IP prefix to create and associate with the NAT Gateway. Must be between 28 and 31."
  type        = number
  default     = 31
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace."
  type        = string
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic settings of the NAT Gateway and of its public IP."
  type        = string
  default     = "DiagnosticsSettings"
}

variable "public_ip_log_categories" {
  description = "(Optional) Specifies the log categories that the diagnostic setting of the public IP sends to the Log Analytics workspace."
  type        = list(string)
  default     = ["DDoSProtectionNotifications", "DDoSMitigationFlowLogs", "DDoSMitigationReports"]
}

variable "public_ip_metric_categories" {
  description = "(Optional) Specifies the metric categories that the diagnostic setting of the public IP sends to the Log Analytics workspace."
  type        = list(string)
  default     = ["AllMetrics"]
}

variable "nat_gateway_log_categories" {
  description = "(Optional) Specifies the log categories that the diagnostic setting of the NAT Gateway sends to the Log Analytics workspace. A Standard NAT Gateway has none: flow logs (NatGatewayFlowlogsV1) are only available for a StandardV2 one."
  type        = list(string)
  default     = []
}

variable "nat_gateway_metric_categories" {
  description = "(Optional) Specifies the metric categories that the diagnostic setting of the NAT Gateway sends to the Log Analytics workspace."
  type        = list(string)
  default     = ["AllMetrics"]
}
