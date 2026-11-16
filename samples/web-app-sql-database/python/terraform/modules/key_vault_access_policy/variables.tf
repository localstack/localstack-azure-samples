variable "key_vault_id" {
  description = "(Required) Specifies the resource id of the Key Vault."
  type        = string
}

variable "tenant_id" {
  description = "(Required) Specifies the Microsoft Entra tenant id of the principal."
  type        = string
}

variable "object_id" {
  description = "(Required) Specifies the object id of the principal the access policy grants permissions to."
  type        = string
}

variable "key_permissions" {
  description = "(Optional) Specifies the key permissions."
  type        = list(string)
  default     = []
}

variable "secret_permissions" {
  description = "(Optional) Specifies the secret permissions."
  type        = list(string)
  default     = []
}

variable "certificate_permissions" {
  description = "(Optional) Specifies the certificate permissions."
  type        = list(string)
  default     = []
}
