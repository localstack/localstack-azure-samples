variable "prefix" {
  description = "Prefix for the name of the Azure resources."
  type        = string
  default     = "local"
}

variable "suffix" {
  description = "Suffix for the name of the Azure resources."
  type        = string
  default     = "payments"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westeurope"
}

variable "eventhub_sku" {
  description = "Event Hubs namespace SKU. Capture and Kafka require Standard or higher."
  type        = string
  default     = "Standard"
}

variable "eventhub_capacity" {
  description = "Throughput units allocated to the namespace."
  type        = number
  default     = 1
}

variable "eventhub_maximum_throughput_units" {
  description = "Upper bound for auto-inflate."
  type        = number
  default     = 4
}

variable "event_hub_name" {
  description = "Name of the event hub carrying payment events."
  type        = string
  default     = "payments"
}

variable "alert_hub_name" {
  description = "Name of the event hub carrying fraud alerts."
  type        = string
  default     = "fraud-alerts"
}

variable "partition_count" {
  description = "Partitions on the payments hub. Partitions are the unit of parallelism."
  type        = number
  default     = 4
}

variable "alert_partition_count" {
  description = "Partitions on the alerts hub."
  type        = number
  default     = 2
}

variable "message_retention_days" {
  description = "Retention for both hubs, in days."
  type        = number
  default     = 1
}

variable "consumer_groups" {
  description = "Consumer groups on the payments hub, one per downstream system."
  type        = list(string)
  default     = ["fraud-detector", "analytics", "audit"]
}

variable "capture_container_name" {
  description = "Blob container that receives Capture archives."
  type        = string
  default     = "payments-archive"
}

variable "capture_interval_in_seconds" {
  description = "Capture flushes after this many seconds, or when the size limit is reached."
  type        = number
  default     = 60
}

variable "capture_size_limit_in_bytes" {
  description = "Capture flushes after this many bytes, or when the interval elapses."
  type        = number
  default     = 10485760
}

variable "schema_group_name" {
  description = "Name of the Schema Registry group holding the payment contract."
  type        = string
  default     = "payments-schemas"
}

variable "fraud_amount_threshold" {
  description = "A single payment at or above this amount is flagged."
  type        = number
  default     = 5000
}

variable "fraud_velocity_count" {
  description = "More than this many payments for one account inside the window is flagged."
  type        = number
  default     = 5
}

variable "fraud_velocity_window_seconds" {
  description = "Velocity window, in seconds."
  type        = number
  default     = 60
}

variable "python_version" {
  description = "Python version for the Function App and the Web App."
  type        = string
  default     = "3.12"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    sample      = "eventhubs-fraud-detection"
    environment = "localstack"
  }
}
