variable "prefix" {
  description = "(Optional) Specifies the prefix for the name of the Azure resources."
  type        = string
  default     = "funcmi"

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

variable "account_kind" {
  description = "(Optional) Specifies the account kind of the storage account."
  default     = "StorageV2"
  type        = string

  validation {
    condition     = contains(["Storage", "StorageV2"], var.account_kind)
    error_message = "The account kind of the storage account is invalid."
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

variable "input_container_name" {
  description = "(Optional) Specifies the name of the input container."
  type        = string
  default     = "input"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.input_container_name))
    error_message = "Container name must be lowercase alphanumeric characters or hyphens, between 3-63 characters."
  }
}

variable "output_container_name" {
  description = "(Optional) Specifies the name of the output container."
  type        = string
  default     = "output"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.output_container_name))
    error_message = "Container name must be lowercase alphanumeric characters or hyphens, between 3-63 characters."
  }
}

variable "os_type" {
  description = "(Required) Specifies the O/S type for the App Services to be hosted in this plan. Possible values include Windows, Linux, and WindowsContainer. Changing this forces a new resource to be created."
  type        = string
  default     = "Linux"

  validation {
    condition = contains([
      "Windows",
      "Linux",
      "WindowsContainer"
    ], var.os_type)
    error_message = "The os_type must be either 'Windows', 'Linux', or 'WindowsContainer'."
  }
}

variable "zone_balancing_enabled" {
  description = "(Optional) Should the Service Plan balance across Availability Zones in the region."
  type        = bool
  default     = false
}

variable "sku_tier" {
  description = "(Optional) Specifies the tier name for the hosting plan."
  type        = string
  default     = "Basic"

  validation {
    condition = contains([
      "Basic",
      "Standard",
      "ElasticPremium",
      "Premium",
      "PremiumV2",
      "Premium0V3",
      "PremiumV3",
      "PremiumMV3",
      "Isolated",
      "IsolatedV2",
      "WorkflowStandard",
      "FlexConsumption"
    ], var.sku_tier)
    error_message = "The sku_tier must be one of the allowed values."
  }
}
variable "sku_name" {
  description = "(Optional) Specifies the SKU name for the hosting plan."
  type        = string
  default     = "B1"

  validation {
    condition = contains([
      "B1", "B2", "B3",
      "S1", "S2", "S3",
      "EP1", "EP2", "EP3",
      "P1v2", "P2v2", "P3v2",
      "P0v3", "P1v3", "P2v3", "P3v3",
      "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
      "I1", "I2", "I3",
      "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2",
      "WS1", "WS2", "WS3",
      "FC1"
    ], var.sku_name)
    error_message = "The sku_name must be one of the allowed values."
  }
}

variable "runtime_name" {
  description = "(Required) Specifies the language runtime used by the Azure Functions App."
  type        = string
  default     = "dotnet-isolated"

  validation {
    condition = contains([
      "dotnet",
      "dotnet-isolated",
      "python",
      "java",
      "node",
      "powerShell",
      "custom"
    ], var.runtime_name)
    error_message = "The runtime_name must be one of the allowed values."
  }
}

variable "dotnet_version" {
  description = "(Optional) Specifies the .NET version for the Azure Functions App, which runs in the isolated worker model."
  type        = string
  default     = "10.0"

  validation {
    condition = contains([
      "8.0",
      "9.0",
      "10.0"
    ], var.dotnet_version)
    error_message = "The dotnet_version must be one of the supported versions: 8.0, 9.0, 10.0."
  }
}

variable "https_only" {
  description = "(Optional) Specifies whether HTTPS is enforced for the Azure Functions App."
  type        = bool
  default     = false
}

variable "minimum_tls_version" {
  description = "(Optional) Specifies the minimum TLS version for the Azure Functions App."
  type        = string
  default     = "1.2"

  validation {
    condition = contains([
      "1.0",
      "1.1",
      "1.2",
      "1.3"
    ], var.minimum_tls_version)
    error_message = "The minimum_tls_version must be one of the allowed values."
  }
}

variable "always_on" {
  description = "(Optional) Specifies whether Always On is enabled for the Azure Functions App."
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "(Optional) Specifies whether the public network access is enabled or disabled."
  type        = bool
  default     = true
}

variable "managed_identity_type" {
  description = "Specifies the type of managed identity."
  type        = string
  default     = "SystemAssigned"

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned"], var.managed_identity_type)
    error_message = "The managed_identity_type must be either 'SystemAssigned' or 'UserAssigned'."
  }
}

variable "tags" {
  description = "(Optional) Specifies the tags to be applied to the resources."
  type        = map(string)
  default = {
    environment = "test"
    iac         = "terraform"
  }
}

variable "diagnostic_settings_name" {
  description = "(Optional) Specifies the name of the diagnostic settings of the function app and of the App Service plan."
  type        = string
  default     = "default"
}

variable "log_categories" {
  description = "(Optional) Specifies the log categories that the diagnostic settings of the function app send to the Log Analytics workspace."
  type        = list(string)
  default = [
    "FunctionAppLogs",
  ]
}

variable "metric_categories" {
  description = "(Optional) Specifies the metric categories that the diagnostic settings of the function app and of the App Service plan send to the Log Analytics workspace."
  type        = list(string)
  default     = ["AllMetrics"]
}
