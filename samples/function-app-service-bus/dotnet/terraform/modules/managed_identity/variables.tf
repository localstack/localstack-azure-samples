variable "name" {
  description = "(Required) Specifies the name of the log analytics workspace"
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the resource group name"
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the log analytics workspace"
  type        = string
}

variable "tags" {
  description = "(Optional) Specifies the tags of the log analytics workspace"
  type        = map(any)
  default     = {}
}

variable "storage_account_id" {
  description = "(Required) Specifies resource id of the Azure Storage Account resource"
  type        = string
}

variable "application_insights_id" {
  description = "(Required) Specifies resource id of the Azure Application Insights resource"
  type        = string
}

variable "service_bus_id" {
  description = "(Required) Specifies resource id of the Azure Service Bus namespace resource"
  type        = string
}
