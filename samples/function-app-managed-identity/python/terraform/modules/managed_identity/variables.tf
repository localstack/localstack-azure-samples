variable "name" {
  description = "(Required) Specifies the name of the user-assigned managed identity. Changing this forces a new resource to be created."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group of the user-assigned managed identity."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location where the user-assigned managed identity is deployed."
  type        = string
}

variable "tags" {
  description = "(Optional) Specifies the tags of the user-assigned managed identity."
  type        = map(any)
  default     = {}
}
