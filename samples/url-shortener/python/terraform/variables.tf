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
