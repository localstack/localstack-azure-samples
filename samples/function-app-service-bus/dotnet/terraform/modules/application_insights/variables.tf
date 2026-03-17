
variable "name" {
  description = "(Required) Specifies the name of the resource. Changing this forces a new resource to be created."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) The name of the resource group in which to create the resource. Changing this forces a new resource to be created."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the supported Azure location where the resource exists. Changing this forces a new resource to be created."
  type        = string
}

variable "application_type" {
  description = "(Required) Specifies the type of Application Insights to create. Valid values are ios for iOS, java for Java web, MobileCenter for App Center, Node.JS for Node.js, other for General, phone for Windows Phone, store for Windows Store and web for ASP.NET. Please note these values are case sensitive; unmatched values are treated as ASP.NET by Azure. Changing this forces a new resource to be created."
  type        = string
  default     = "web"
}

variable "workspace_id" {
  description = "(Optional) Specifies the id of a log analytics workspace resource. Changing this forces a new resource to be created."
  type        = string
}

variable "tags" {
  description = "(Optional) Specifies the tags to be applied to the resources"
  type        = map(any)
  default     = {}
}

variable "disable_ip_masking" {
  description = "(Optional) Specifies whether IP masking is disabled."
  type        = bool
  default     = false
}

variable "local_authentication_disabled" {
  description = "(Optional) Specifies whether local authentication is disabled."
  type        = bool
  default     = false
}

variable "internet_ingestion_enabled" {
  description = "(Optional) Specifies whether the public network access for ingestion is enabled."
  type        = bool
  default     = true
}

variable "internet_query_enabled" {
  description = "(Optional) Specifies whether the public network access for query is enabled."
  type        = bool
  default     = true
}