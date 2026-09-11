variable "name" {
  description = "(Required) Specifies the name of the Key Vault. Globally unique, 3 to 24 alphanumerics and hyphens. Changing this forces a new resource to be created."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group of the Key Vault."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location where the Key Vault is deployed."
  type        = string
}

variable "tenant_id" {
  description = "(Required) Specifies the Microsoft Entra tenant id used for authenticating requests to the Key Vault."
  type        = string
}

variable "sku_name" {
  description = "(Optional) Specifies the SKU of the Key Vault: standard or premium. Defaults to standard."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "The sku_name must be standard or premium."
  }
}

variable "enabled_for_deployment" {
  description = "(Optional) Specifies whether Azure Virtual Machines are permitted to retrieve certificates stored as secrets from the Key Vault. Defaults to false."
  type        = bool
  default     = false
}

variable "enabled_for_disk_encryption" {
  description = "(Optional) Specifies whether Azure Disk Encryption is permitted to retrieve secrets from the Key Vault and unwrap keys. Defaults to false."
  type        = bool
  default     = false
}

variable "enabled_for_template_deployment" {
  description = "(Optional) Specifies whether Azure Resource Manager is permitted to retrieve secrets from the Key Vault. Defaults to false."
  type        = bool
  default     = false
}

variable "rbac_authorization_enabled" {
  description = "(Optional) Specifies whether the Key Vault uses Azure RBAC for data-plane authorization instead of access policies. The Key Vault Secrets User and Key Vault Secrets Officer roles only work with it. Defaults to true."
  type        = bool
  default     = true
}

variable "purge_protection_enabled" {
  description = "(Optional) Specifies whether purge protection is enabled for the Key Vault. Defaults to false, so a destroyed vault can be purged and its name reused."
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "(Optional) Specifies for how many days a deleted Key Vault or secret stays recoverable, between 7 and 90. Defaults to 7."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "The soft_delete_retention_days must be between 7 and 90."
  }
}

variable "public_network_access_enabled" {
  description = "(Optional) Specifies whether the Key Vault accepts requests from public networks. Defaults to true, so a deployment running outside the virtual network can write the secrets; workloads inside the network use the private endpoint."
  type        = bool
  default     = true
}

variable "secrets" {
  description = "(Optional) Specifies the secrets to create in the Key Vault: a map of secret name to secret value. Secret names allow only alphanumerics and hyphens. Marked sensitive; the names are used as resource keys, the values are never shown."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "deployer_object_id" {
  description = "(Optional) Specifies the object id of the principal running terraform apply. It is granted the deployer role on the Key Vault before the secrets are written, because azurerm_key_vault_secret uses the data plane, which on an RBAC vault requires a data-plane role. Empty skips the assignment."
  type        = string
  default     = ""
}

variable "deployer_principal_type" {
  description = "(Optional) Specifies the principal type of the deploying principal: User, Group or ServicePrincipal. Defaults to User."
  type        = string
  default     = "User"

  validation {
    condition     = contains(["User", "Group", "ServicePrincipal"], var.deployer_principal_type)
    error_message = "The deployer_principal_type must be User, Group or ServicePrincipal."
  }
}

variable "deployer_role_definition_name" {
  description = "(Optional) Specifies the role granted to the deploying principal on the Key Vault. Defaults to Key Vault Secrets Officer, which allows any action on secrets except managing permissions."
  type        = string
  default     = "Key Vault Secrets Officer"
}

variable "rbac_propagation_delay" {
  description = "(Optional) Specifies how long to wait after the deploying principal's role assignment before writing the secrets: Azure role assignments take a while to propagate. Defaults to 60s; pass 0s where propagation is immediate."
  type        = string
  default     = "60s"
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace the diagnostic settings send logs and metrics to."
  type        = string
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic setting of the Key Vault. Defaults to default."
  type        = string
  default     = "default"
}

variable "log_categories" {
  description = "(Optional) Specifies the log categories the diagnostic setting enables."
  type        = list(string)
  default     = ["AuditEvent", "AzurePolicyEvaluationDetails"]
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories the diagnostic setting enables."
  type        = list(string)
  default     = ["AllMetrics"]
}

variable "tags" {
  description = "(Optional) Specifies the tags of the Key Vault and its secrets."
  type        = map(any)
  default     = {}
}
