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
  description = "SKU of the Linux App Service plan hosting the Function App."
  type        = string
  default     = "B1"
}

variable "python_version" {
  description = "Python version of the Function App."
  type        = string
  default     = "3.11"
}

variable "backend_scheme" {
  description = "Scheme API Management uses to call the Function App. The emulator serves it over plain HTTP; use https on real Azure."
  type        = string
  default     = "http"

  validation {
    condition     = contains(["http", "https"], var.backend_scheme)
    error_message = "backend_scheme must be http or https."
  }
}

variable "apim_sku_name" {
  description = "SKU of the API Management service, as <tier>_<capacity>. Consumption provisions in minutes; the classic tiers take much longer."
  type        = string
  default     = "Consumption_0"
}

variable "publisher_name" {
  description = "Name of the organisation publishing the APIs."
  type        = string
  default     = "LocalStack"
}

variable "publisher_email" {
  description = "E-mail address API Management sends its notifications to."
  type        = string
  default     = "noreply@localstack.cloud"
}
