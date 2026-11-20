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
  description = "(Optional) Specifies the tier of the namespace. Capture and Kafka need Standard or higher."
  type        = string
  default     = "Standard"
}

variable "capacity" {
  description = "(Optional) Specifies the throughput units allocated to the namespace."
  type        = number
  default     = 1
}

variable "maximum_throughput_units" {
  description = "(Optional) Specifies the upper bound of auto-inflate."
  type        = number
  default     = 4
}

variable "event_hub_name" {
  description = "(Required) Specifies the name of the hub carrying the payments, which Capture archives."
  type        = string
}

variable "alert_hub_name" {
  description = "(Required) Specifies the name of the hub carrying the fraud alerts."
  type        = string
}

variable "partition_count" {
  description = "(Optional) Specifies the number of partitions of the payments hub, the unit of parallelism."
  type        = number
  default     = 4
}

variable "alert_partition_count" {
  description = "(Optional) Specifies the number of partitions of the alerts hub."
  type        = number
  default     = 2
}

variable "message_retention_days" {
  description = "(Optional) Specifies the message retention of both hubs, in days."
  type        = number
  default     = 1
}

variable "consumer_groups" {
  description = "(Required) Specifies the consumer groups of the payments hub, one per downstream system."
  type        = list(string)
}

variable "capture_container_name" {
  description = "(Required) Specifies the blob container that receives the Capture archives."
  type        = string
}

variable "capture_storage_account_id" {
  description = "(Required) Specifies the resource id of the storage account of the Capture archives."
  type        = string
}

variable "capture_interval_in_seconds" {
  description = "(Optional) Specifies the time window of a Capture archive, in seconds."
  type        = number
  default     = 60
}

variable "capture_size_limit_in_bytes" {
  description = "(Optional) Specifies the size window of a Capture archive, in bytes."
  type        = number
  default     = 10485760
}

variable "schema_group_name" {
  description = "(Required) Specifies the name of the Schema Registry group holding the payment contract."
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
