variable "name" {
  description = "(Required) Specifies the name of the API Management service."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the API Management service."
  type        = string
}

variable "publisher_name" {
  description = "(Required) Specifies the name of the organisation publishing the APIs."
  type        = string
}

variable "publisher_email" {
  description = "(Required) Specifies the e-mail address API Management sends its notifications to."
  type        = string
}

variable "sku_name" {
  description = "(Optional) Specifies the SKU of the API Management service, as <tier>_<capacity>."
  type        = string
  default     = "Consumption_0"
}

variable "named_value_id" {
  description = "(Optional) Specifies the id of the secret named value the policy refers to as {{backend-secret}}."
  type        = string
  default     = "backend-secret"
}

variable "backend_secret" {
  description = "(Required) Specifies the shared secret the gateway adds to every backend call."
  type        = string
  sensitive   = true
}

variable "api_id" {
  description = "(Optional) Specifies the id of the API."
  type        = string
  default     = "inventory-api"
}

variable "api_path" {
  description = "(Optional) Specifies the URL suffix of the API on the gateway."
  type        = string
  default     = "inventory"
}

variable "service_url" {
  description = "(Required) Specifies the URL of the backend the API forwards to: the Function App."
  type        = string
}

variable "open_api_document" {
  description = "(Required) Specifies the OpenAPI document the API is imported from."
  type        = string
}

variable "api_policy" {
  description = "(Required) Specifies the policy of the API, in raw XML."
  type        = string
}

variable "product_id" {
  description = "(Optional) Specifies the id of the product."
  type        = string
  default     = "inventory-partners"
}

variable "subscription_id" {
  description = "(Optional) Specifies the id of the subscription whose key clients present."
  type        = string
  default     = "partner-subscription"
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace the diagnostic setting sends to."
  type        = string
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic setting."
  type        = string
  default     = "default"
}

variable "log_categories" {
  description = "(Optional) Specifies the log categories the diagnostic setting enables. Defaults to none on the Consumption tier, which doesn't support the collection of resource logs, and to GatewayLogs on the other tiers."
  type        = list(string)
  default     = null
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories the diagnostic setting enables."
  type        = list(string)
  default     = ["AllMetrics"]
}

variable "log_analytics_destination_type" {
  description = "(Optional) Specifies where the diagnostic setting writes the logs in the workspace: Dedicated writes the gateway logs to the resource-specific ApiManagementGatewayLogs table, AzureDiagnostics to the shared AzureDiagnostics table."
  type        = string
  default     = "Dedicated"

  validation {
    condition     = contains(["AzureDiagnostics", "Dedicated"], var.log_analytics_destination_type)
    error_message = "The log_analytics_destination_type must be AzureDiagnostics or Dedicated."
  }
}

variable "tags" {
  description = "(Optional) Specifies the tags of the resources."
  type        = map(string)
  default     = {}
}
