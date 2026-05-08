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

variable "acr_id" {
  description = "(Required) Specifies resource id of the Azure Container Registry resource"
  type        = string
}

