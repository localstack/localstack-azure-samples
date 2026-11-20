variable "name" {
  description = "(Required) Specifies the name of the Event Hubs namespace."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the namespace."
  type        = string
}

variable "sku" {
  description = "(Optional) Specifies the tier of the namespace. Capture needs Standard or higher."
  type        = string
  default     = "Standard"
}

variable "telemetry_hub_name" {
  description = "(Required) Specifies the name of the hub that Capture archives."
  type        = string
}

variable "notification_hub_name" {
  description = "(Required) Specifies the name of the hub the Event Grid notifications are delivered to."
  type        = string
}

variable "curated_hub_name" {
  description = "(Required) Specifies the name of the hub the per-device summaries are written to."
  type        = string
}

variable "telemetry_partition_count" {
  description = "(Optional) Specifies the number of partitions of the telemetry hub."
  type        = number
  default     = 2
}

variable "retention_days" {
  description = "(Optional) Specifies the message retention of the hubs, in days."
  type        = number
  default     = 1
}

variable "capture_interval_seconds" {
  description = "(Optional) Specifies the time window of a Capture archive, in seconds."
  type        = number
  default     = 60
}

variable "capture_size_limit_bytes" {
  description = "(Optional) Specifies the size window of a Capture archive, in bytes."
  type        = number
  default     = 10485760
}

variable "capture_container_name" {
  description = "(Required) Specifies the blob container that receives the Capture archives."
  type        = string
}

variable "capture_storage_account_id" {
  description = "(Required) Specifies the resource id of the storage account of the Capture archives."
  type        = string
}

variable "capture_consumer_group" {
  description = "(Required) Specifies the consumer group the processor reads the notifications with."
  type        = string
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
  description = "(Optional) Specifies the log categories the diagnostic setting of the namespace enables. ArchiveLogs records the Capture archives; the runtime audit logs are left out, since Event Hubs writes them only in the Premium and Dedicated tiers."
  type        = list(string)
  default = [
    "ArchiveLogs",
    "OperationalLogs",
    "AutoScaleLogs",
    "KafkaCoordinatorLogs",
    "KafkaUserErrorLogs",
    "EventHubVNetConnectionEvent",
    "CustomerManagedKeyUserLogs",
    "ApplicationMetricsLogs",
    "DiagnosticErrorLogs",
    "DataDRLogs",
  ]
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories the diagnostic setting enables."
  type        = list(string)
  default     = ["AllMetrics"]
}

variable "log_analytics_destination_type" {
  description = "(Optional) Specifies where the diagnostic setting writes the logs: Dedicated writes the operational logs to the resource-specific AZMSOperationalLogs table; the other categories have AzureDiagnostics only."
  type        = string
  default     = "Dedicated"
}

variable "tags" {
  description = "(Optional) Specifies the tags of the resources."
  type        = map(string)
  default     = {}
}
