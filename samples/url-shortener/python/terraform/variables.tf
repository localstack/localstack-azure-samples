variable "prefix" {
  description = "Prefix applied to every resource name in this sample."
  type        = string
  default     = "local"
}

variable "suffix" {
  description = "Suffix applied to every resource name in this sample."
  type        = string
  default     = "test"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westeurope"
}

variable "storage_allow_nested_items_to_be_public" {
  description = "Allow containers in the storage account to grant anonymous read access. The qrcodes container serves the QR code images publicly, and new storage accounts disallow anonymous access unless the account explicitly allows it."
  type        = bool
  default     = true
}

variable "app_service_plan_sku" {
  description = "SKU of the Linux App Service Plan shared by the web app and the worker."
  type        = string
  default     = "B1"
}

variable "postgres_sku_name" {
  description = "SKU of the PostgreSQL flexible server."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_version" {
  description = "Major version of the PostgreSQL flexible server."
  type        = string
  default     = "16"
}

variable "postgres_storage_mb" {
  description = "Storage size of the PostgreSQL flexible server in MB."
  type        = number
  default     = 32768
}

variable "servicebus_sku" {
  description = "SKU of the Service Bus namespace."
  type        = string
  default     = "Standard"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    environment = "test"
    iac         = "terraform"
  }
}

variable "log_analytics_sku" {
  description = "SKU of the Log Analytics workspace."
  type        = string
  default     = "PerGB2018"
}

variable "log_analytics_retention_in_days" {
  description = "Data retention of the Log Analytics workspace in days."
  type        = number
  default     = 30
}

variable "deployer_object_id" {
  description = "Object id of the principal that runs terraform apply. It gets Key Vault Secrets Officer on the vault, which azurerm_key_vault_secret needs to write the secrets through the data plane; with an empty value the role must already be assigned."
  type        = string
  default     = ""
}

variable "deployer_principal_type" {
  description = "Type of the principal that runs terraform apply: User or ServicePrincipal."
  type        = string
  default     = "User"
}
