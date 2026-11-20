variable "scope" {
  description = "(Required) Specifies the scope the role is assigned at: the resource id of a resource, a resource group or a subscription. Changing this forces a new resource to be created."
  type        = string
}

variable "role_definition_name" {
  description = "(Required) Specifies the name of the built-in or custom role to assign, for example App Configuration Data Reader. Changing this forces a new resource to be created."
  type        = string
}

variable "principal_id" {
  description = "(Required) Specifies the principal (object) id of the user, group or service principal the role is assigned to. For a managed identity this is its principal id, never its client id. Changing this forces a new resource to be created."
  type        = string
}

variable "principal_type" {
  description = "(Optional) Specifies the type of the principal: User, Group or ServicePrincipal. Passing it lets Azure create the assignment before a new principal is replicated across Microsoft Entra ID."
  type        = string
  default     = "ServicePrincipal"

  validation {
    condition     = contains(["User", "Group", "ServicePrincipal"], var.principal_type)
    error_message = "The principal_type must be User, Group or ServicePrincipal."
  }
}

variable "skip_service_principal_aad_check" {
  description = "(Optional) Specifies whether to skip the Microsoft Entra ID check for the service principal in the request. Defaults to false."
  type        = bool
  default     = false
}

variable "description" {
  description = "(Optional) Specifies the description of the role assignment."
  type        = string
  default     = null
}
