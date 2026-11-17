variable "name" {
  description = "(Required) Specifies the name of the system topic."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the system topic."
  type        = string
}

variable "source_resource_id" {
  description = "(Required) Specifies the resource id of the Event Hubs namespace whose events the topic carries."
  type        = string
}

variable "subscription_name" {
  description = "(Required) Specifies the name of the event subscription."
  type        = string
}

variable "eventhub_id" {
  description = "(Required) Specifies the resource id of the event hub the notifications are delivered to."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace the diagnostic setting sends to."
  type        = string
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic setting."
  type        = string
  default     = "default"
}

variable "tags" {
  description = "(Optional) Specifies the tags of the resources."
  type        = map(string)
  default     = {}
}
