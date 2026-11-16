variable "server_id" {
  description = "(Required) Specifies the resource id of the SQL server."
  type        = string
}

variable "key_vault_key_id" {
  description = "(Required) Specifies the id of the Key Vault key used as the TDE protector."
  type        = string
}

variable "auto_rotation_enabled" {
  description = "(Optional) Specifies whether the server follows new versions of the key automatically."
  type        = bool
  default     = true
}
