variable "prefix" {
  description = "(Optional) Specifies the prefix for the name of the Azure resources."
  type        = string
  default     = "local"

  validation {
    condition     = var.prefix == null || length(var.prefix) >= 2
    error_message = "The prefix must be at least 2 characters long."
  }
}

variable "suffix" {
  description = "(Optional) Specifies the suffix for the name of the Azure resources."
  type        = string
  default     = "test"

  validation {
    condition     = var.suffix == null || length(var.suffix) >= 2
    error_message = "The suffix must be at least 2 characters long."
  }
}

variable "location" {
  description = "(Required) Specifies the location for all resources."
  type        = string
  default     = "westeurope"
}

variable "tags" {
  description = "(Optional) Specifies the tags to be applied to the resources."
  type        = map(string)
  default = {
    environment = "test"
    iac         = "terraform"
  }
}

variable "queue_name" {
  description = "(Optional) Specifies the name of the Service Bus Queue."
  type        = string
  default     = "myqueue"
}

# Service Bus Namespace Variables

variable "servicebus_namespace_sku" {
  description = "(Required) Specifies the SKU tier for the Service Bus Namespace. Options are Basic, Standard, or Premium."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.servicebus_namespace_sku)
    error_message = "The SKU must be one of Basic, Standard, or Premium."
  }
}

variable "servicebus_namespace_capacity" {
  description = "(Optional) Specifies the capacity for the Service Bus Namespace. When SKU is Premium, capacity can be 1, 2, 4, 8, or 16. When SKU is Basic or Standard, capacity can be 0 only."
  type        = number
  default     = 0
}

variable "servicebus_namespace_premium_messaging_partitions" {
  description = "(Optional) Specifies the number of messaging partitions. Only valid when SKU is Premium. Possible values include 0, 1, 2, and 4. Defaults to 0."
  type        = number
  default     = 0
}

variable "servicebus_namespace_local_auth_enabled" {
  description = "(Optional) Specifies whether SAS authentication is enabled for the Service Bus Namespace. Defaults to true."
  type        = bool
  default     = true
}

variable "servicebus_namespace_public_network_access_enabled" {
  description = "(Optional) Specifies whether public network access is enabled for the Service Bus Namespace. Defaults to true."
  type        = bool
  default     = true
}

variable "servicebus_namespace_minimum_tls_version" {
  description = "(Optional) Specifies the minimum supported TLS version for the Service Bus Namespace. Valid values are 1.0, 1.1, and 1.2. Defaults to 1.2."
  type        = string
  default     = "1.2"

  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.servicebus_namespace_minimum_tls_version)
    error_message = "The minimum TLS version must be one of 1.0, 1.1, or 1.2."
  }
}

# Service Bus Queue Variables

variable "servicebus_queue_lock_duration" {
  description = "(Optional) Specifies the ISO 8601 timespan duration of a peek-lock. Maximum value is 5 minutes. Defaults to PT1M."
  type        = string
  default     = "PT4M"
}

variable "servicebus_queue_max_message_size_in_kilobytes" {
  description = "(Optional) Specifies the maximum size of a message allowed on the queue in kilobytes. Only applicable for Premium SKU."
  type        = number
  default     = null
}

variable "servicebus_queue_max_size_in_megabytes" {
  description = "(Optional) Specifies the size of memory allocated for the queue in megabytes."
  type        = number
  default     = null
}

variable "servicebus_queue_requires_duplicate_detection" {
  description = "(Optional) Specifies whether the queue requires duplicate detection. Changing this forces a new resource to be created. Defaults to false."
  type        = bool
  default     = true
}

variable "servicebus_queue_requires_session" {
  description = "(Optional) Specifies whether the queue requires sessions for ordered handling of unbounded sequences of related messages. Changing this forces a new resource to be created. Defaults to false."
  type        = bool
  default     = true
}

variable "servicebus_queue_default_message_ttl" {
  description = "(Optional) Specifies the ISO 8601 timespan duration of the TTL of messages sent to this queue."
  type        = string
  default     = "PT12S"
}

variable "servicebus_queue_dead_lettering_on_message_expiration" {
  description = "(Optional) Specifies whether the queue has dead letter support when a message expires. Defaults to false."
  type        = bool
  default     = true
}

variable "servicebus_queue_duplicate_detection_history_time_window" {
  description = "(Optional) Specifies the ISO 8601 timespan duration during which duplicates can be detected. Defaults to PT10M."
  type        = string
  default     = "PT10M"
}

variable "servicebus_queue_max_delivery_count" {
  description = "(Optional) Specifies the maximum number of deliveries before a message is automatically dead lettered. Defaults to 10."
  type        = number
  default     = 5
}

variable "servicebus_queue_status" {
  description = "(Optional) Specifies the status of the queue. Possible values are Active, Creating, Deleting, Disabled, ReceiveDisabled, Renaming, SendDisabled, Unknown. Defaults to Active."
  type        = string
  default     = "Active"
}

variable "servicebus_queue_batched_operations_enabled" {
  description = "(Optional) Specifies whether server-side batched operations are enabled. Defaults to true."
  type        = bool
  default     = true
}

variable "servicebus_queue_auto_delete_on_idle" {
  description = "(Optional) Specifies the ISO 8601 timespan duration of the idle interval after which the queue is automatically deleted. Minimum of 5 minutes."
  type        = string
  default     = null
}

variable "servicebus_queue_partitioning_enabled" {
  description = "(Optional) Specifies whether the queue is partitioned across multiple message brokers. Changing this forces a new resource to be created. Defaults to false."
  type        = bool
  default     = true
}

variable "servicebus_queue_express_enabled" {
  description = "(Optional) Specifies whether Express Entities are enabled. An express queue holds a message in memory temporarily before writing it to persistent storage. Defaults to false."
  type        = bool
  default     = true
}

variable "servicebus_queue_forward_to" {
  description = "(Optional) Specifies the name of a queue or topic to automatically forward messages to."
  type        = string
  default     = null
}

variable "servicebus_queue_forward_dead_lettered_messages_to" {
  description = "(Optional) Specifies the name of a queue or topic to automatically forward dead lettered messages to."
  type        = string
  default     = null
}