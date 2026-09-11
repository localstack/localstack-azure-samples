variable "name" {
  description = "(Required) Specifies the name of the App Configuration store. Globally unique, 5 to 50 alphanumerics and hyphens. Changing this forces a new resource to be created."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group of the App Configuration store."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location where the App Configuration store is deployed."
  type        = string
}

variable "sku" {
  description = "(Optional) Specifies the SKU of the App Configuration store: free, developer, standard or premium. Private endpoints need developer, standard or premium. Defaults to standard."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["free", "developer", "standard", "premium"], var.sku)
    error_message = "The sku must be free, developer, standard or premium."
  }
}

variable "local_auth_enabled" {
  description = "(Optional) Specifies whether the access keys of the store stay enabled. The key-values are written through Azure Resource Manager, which in the default Local authentication mode relies on the access keys, so this must stay true unless the store's ARM authentication mode is switched to Pass-through. Defaults to true."
  type        = bool
  default     = true
}

variable "public_network_access" {
  description = "(Optional) Specifies whether the store accepts requests from public networks: Enabled or Disabled. Defaults to Enabled, so a deployment running outside the virtual network can seed the store; workloads inside the network use the private endpoint."
  type        = string
  default     = "Enabled"

  validation {
    condition     = contains(["Enabled", "Disabled"], var.public_network_access)
    error_message = "The public_network_access must be Enabled or Disabled."
  }
}

variable "purge_protection_enabled" {
  description = "(Optional) Specifies whether purge protection is enabled for the store. Defaults to false, so a destroyed store can be purged and its name reused."
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "(Optional) Specifies for how many days a deleted store stays recoverable, between 1 and 7. Defaults to 7."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 7
    error_message = "The soft_delete_retention_days must be between 1 and 7."
  }
}

variable "key_values" {
  description = "(Optional) Specifies the key-values to seed in the store, by key. Each entry has a value, an optional content type (application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8 for a Key Vault reference whose value is {\"uri\":\"<secret identifier>\"}) and an optional label."
  type = map(object({
    value        = string
    content_type = optional(string)
    label        = optional(string)
  }))
  default = {}
}

variable "key_value_api_version" {
  description = "(Optional) Specifies the API version of the Microsoft.AppConfiguration/configurationStores/keyValues resource type the key-values are created with. Defaults to 2024-06-01."
  type        = string
  default     = "2024-06-01"
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace the diagnostic settings send logs and metrics to."
  type        = string
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic setting of the store. Defaults to default."
  type        = string
  default     = "default"
}

variable "log_categories" {
  description = "(Optional) Specifies the log categories the diagnostic setting enables."
  type        = list(string)
  default     = ["HttpRequest", "Audit"]
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories the diagnostic setting enables."
  type        = list(string)
  default     = ["AllMetrics"]
}

variable "tags" {
  description = "(Optional) Specifies the tags of the App Configuration store."
  type        = map(any)
  default     = {}
}
