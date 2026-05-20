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
  default     = null
}

variable "account_replication_type" {
  description = "(Optional) Specifies the replication type for the storage account."
  type        = string
  default     = "LRS"

  validation {
    condition = contains([
      "LRS",
      "GRS",
      "RAGRS",
      "ZRS",
      "GZRS",
      "RAGZRS"
    ], var.account_replication_type)
    error_message = "The account_replication_type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "account_tier" {
  description = "(Optional) Specifies the account tier of the storage account."
  default     = "Standard"
  type        = string

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "The account tier of the storage account is invalid."
  }
}

variable "blob_container_name" {
  description = "(Optional) Specifies the name of the blob container."
  type        = string
  default     = "activities"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.blob_container_name))
    error_message = "Container name must be lowercase alphanumeric characters or hyphens."
  }
}

variable "image_name" {
  description = "(Optional) Specifies the name of the container image."
  type        = string
  default     = "vacation-planner"
}

variable "image_tag" {
  description = "(Optional) Specifies the tag of the container image."
  type        = string
  default     = "v1"
}

variable "cpu_cores" {
  description = "(Optional) Specifies the number of CPU cores for the container."
  type        = number
  default     = 1
}

variable "memory_in_gb" {
  description = "(Optional) Specifies the memory in GB for the container."
  type        = number
  default     = 1
}

variable "login_name" {
  description = "(Optional) Specifies the login name passed to the app."
  type        = string
  default     = "paolo"
}

variable "tags" {
  description = "(Optional) Specifies the tags to be applied to the resources."
  type        = map(string)
  default = {
    environment = "test"
    iac         = "terraform"
  }
}
