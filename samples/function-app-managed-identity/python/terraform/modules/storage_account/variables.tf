variable "name" {
  description = "(Required) Specifies the globally unique name of the storage account. Changing this forces a new resource to be created."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group of the storage account."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the storage account."
  type        = string
}

variable "account_kind" {
  description = "(Optional) Specifies the account kind of the storage account."
  type        = string
  default     = "StorageV2"

  validation {
    condition     = contains(["Storage", "StorageV2", "BlobStorage", "BlockBlobStorage", "FileStorage"], var.account_kind)
    error_message = "The account_kind must be one of: Storage, StorageV2, BlobStorage, BlockBlobStorage, FileStorage."
  }
}

variable "account_tier" {
  description = "(Optional) Specifies the account tier of the storage account."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "The account_tier must be Standard or Premium."
  }
}

variable "account_replication_type" {
  description = "(Optional) Specifies the replication type of the storage account."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RA-GRS", "RA-GZRS"], var.account_replication_type)
    error_message = "The account_replication_type must be one of: LRS, ZRS, GRS, GZRS, RA-GRS, RA-GZRS."
  }
}

variable "container_names" {
  description = "(Optional) Specifies the names of the blob containers to create."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the resource id of the Log Analytics workspace."
  type        = string
}

variable "diagnostic_setting_name" {
  description = "(Optional) Specifies the name of the diagnostic settings of the storage account and of its blob service."
  type        = string
  default     = "default"
}

variable "diagnostic_services" {
  description = "(Optional) Specifies the services of the storage account whose diagnostic settings send their resource logs and metrics to the Log Analytics workspace: blob (StorageBlobLogs), queue (StorageQueueLogs), table (StorageTableLogs), file (StorageFileLogs)."
  type        = list(string)
  default     = ["blob"]

  validation {
    condition     = alltrue([for service in var.diagnostic_services : contains(["blob", "queue", "table", "file"], service)])
    error_message = "The diagnostic_services can hold only blob, queue, table and file."
  }
}

variable "service_log_categories" {
  description = "(Optional) Specifies the log categories that the diagnostic settings of the services send to the Log Analytics workspace."
  type        = list(string)
  default     = ["StorageRead", "StorageWrite", "StorageDelete"]
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories that the diagnostic settings of the storage account and of its blob service send to the Log Analytics workspace (AzureMetrics table): Capacity holds the hourly capacity metrics, Transaction the metrics of the requests."
  type        = list(string)
  default     = ["Capacity", "Transaction"]
}

variable "tags" {
  description = "(Optional) Specifies the tags of the storage account."
  type        = map(any)
  default     = {}
}
