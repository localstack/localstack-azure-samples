variable "prefix" {
  description = "Prefix for every resource name."
  type        = string
  default     = "local"
}

variable "suffix" {
  description = "Suffix for every resource name."
  type        = string
  default     = "telemetry"
}

variable "location" {
  description = "Azure region for every resource."
  type        = string
  default     = "westeurope"
}

variable "eventhub_sku" {
  description = "Event Hubs namespace SKU. Capture requires Standard or higher."
  type        = string
  default     = "Standard"
}

variable "telemetry_hub_name" {
  description = "Hub that receives device telemetry and is archived by Capture."
  type        = string
  default     = "telemetry"
}

variable "notification_hub_name" {
  description = "Hub that receives the CaptureFileCreated notifications from Event Grid."
  type        = string
  default     = "capture-notifications"
}

variable "curated_hub_name" {
  description = "Hub that receives the curated per-device summaries."
  type        = string
  default     = "curated"
}

variable "telemetry_partition_count" {
  description = "Partitions on the telemetry hub."
  type        = number
  default     = 4
}

variable "retention_days" {
  description = "Retention for every hub, in days."
  type        = number
  default     = 1
}

variable "capture_interval_seconds" {
  description = "Capture flush interval, in seconds. 60 is the minimum Azure allows."
  type        = number
  default     = 60
}

variable "capture_size_limit_bytes" {
  description = "Capture flush size limit, in bytes."
  type        = number
  default     = 10485760
}

variable "capture_container_name" {
  description = "Blob container that receives Capture archives."
  type        = string
  default     = "telemetry-archive"
}

variable "capture_consumer_group" {
  description = "Consumer group the processor reads the notifications hub with."
  type        = string
  default     = "capture-processor"
}

variable "event_subscription_name" {
  description = "Name of the Event Grid subscription delivering to the notifications hub."
  type        = string
  default     = "capture-to-eventhub"
}

variable "temperature_limit" {
  description = "A reading at or above this is reported as an excursion on the device summary."
  type        = number
  default     = 80
}

variable "python_version" {
  description = "Python version for the Function App."
  type        = string
  default     = "3.12"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    sample      = "eventhubs-eventgrid"
    environment = "localstack"
  }
}
