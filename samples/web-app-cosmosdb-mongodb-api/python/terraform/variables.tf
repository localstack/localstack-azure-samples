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

variable "primary_region" {
  description = "(Required) Specifies the primary region for the Azure Cosmos DB account."
  type        = string
  default     = "westeurope"
}

variable "secondary_region" {
  description = "(Required) Specifies the secondary region for the Azure Cosmos DB account."
  type        = string
  default     = "northeurope"
}

variable "mongodb_server_version" {
  description = "(Optional) Specifies the version of MongoDB API for the Azure Cosmos DB account."
  type        = string
  default     = "7.0"

  validation {
    condition = contains([
      "3.2",
      "3.6",
      "4.0",
      "4.2",
      "5.0",
      "6.0",
      "7.0",
      "8.0"
    ], var.mongodb_server_version)
    error_message = "The mongodb_server_version must be one of the supported versions: 3.2, 3.6, 4.0, 4.2, 5.0, 6.0, 7.0, 8.0."
  }
}

variable "database_throughput" {
  description = "(Optional) Specifies the throughput for the MongoDB database."
  type        = number
  default     = 400
}

variable "consistency_level" {
  description = "(Required) Specifies the consistency level for the Azure Cosmos DB account."
  type        = string
  default     = "Eventual"

  validation {
    condition = contains([
      "Strong",
      "BoundedStaleness",
      "Session",
      "Eventual"
    ], var.consistency_level)
    error_message = "The consistency_level must be one of the allowed values."
  }
}

variable "cosmosdb_database_name" {
  description = "(Optional) Specifies the name of the Azure Cosmos DB for MongoDB database."
  type        = string
  default     = "sampledb"
}

variable "cosmosdb_collection_name" {
  description = "(Optional) Specifies the name of the Azure Cosmos DB for MongoDB collection."
  type        = string
  default     = "activities"
}

variable "mongodb_index_keys" {
  description = "A list of field names for which to create single-field indexes on the MongoDB collection."
  type        = list(string)
  default     = ["_id", "username", "activity", "timestamp"]
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
  default     = "Standard"

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
  default     = "S1"

  validation {
    condition = contains([
      "B1", "B2", "B3",
      "S1", "S2", "S3",
      "EP1", "EP2", "EP3",
      "P1", "P2", "P3",
      "P1V2", "P2V2", "P3V2",
      "P0V3", "P1V3", "P2V3", "P3V3",
      "P1MV3", "P2MV3", "P3MV3", "P4MV3", "P5MV3",
      "I1", "I2", "I3",
      "I1V2", "I2V2", "I3V2", "I4V2", "I5V2", "I6V2",
      "WS1", "WS2", "WS3",
      "FC1"
    ], var.sku_name)
    error_message = "The sku_name must be one of the allowed values."
  }
}

variable "python_version" {
  description = "(Optional) Specifies the version of Python to run. Possible values include 3.13, 3.12, 3.11, 3.10, 3.9, 3.8 and 3.7."
  type        = string
  default     = "3.12"

  validation {
    condition = contains([
      "3.13",
      "3.12",
      "3.11",
      "3.10",
      "3.9",
      "3.8",
      "3.7"
    ], var.python_version)
    error_message = "The python_version must be one of the supported versions: 3.13, 3.12, 3.11, 3.10, 3.9, 3.8, 3.7."
  }
}

variable "https_only" {
  description = "(Optional) Specifies whether the Linux Web App require HTTPS connections. Defaults to false."
  type        = bool
  default     = false
}

variable "minimum_tls_version" {
  description = "(Optional) Specifies the minimum version of TLS required for SSL requests. Possible values include: 1.0, 1.1, 1.2 and 1.3. Defaults to 1.2."
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
  description = "(Optional) Specifies whether the Linux Web App is Always On enabled. Defaults to true."
  type        = bool
  default     = true
}

variable "http2_enabled" {
  description = "(Optional) Specifies whether HTTP/2 is enabled for the Linux Web App."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "(Optional) Specifies whether the public network access is enabled or disabled."
  type        = bool
  default     = true
}

variable "repo_url" {
  description = "(Optional) Specifies the Git repository URL."
  type        = string
  default     = ""

  validation {
    condition     = var.repo_url == "" || can(regex("^https?://", var.repo_url))
    error_message = "The repo_url must be empty or a valid HTTP/HTTPS URL."
  }
}

variable "login_name" {
  description = "(Required) Specifies the login name for the application."
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

variable "vnet_name" {
  description = "Specifies the name of the virtual network."
  default     = "VNet"
  type        = string
}

variable "vnet_address_space" {
  description = "Specifies the address space of the virtual network."
  default     = ["10.0.0.0/8"]
  type        = list(string)
}

variable "webapp_subnet_name" {
  description = "Specifies the name of the web app subnet."
  default     = "app-subnet"
  type        = string
}

variable "webapp_subnet_address_prefix" {
  description = "Specifies the address prefix of the web app subnet."
  default     = ["10.0.0.0/24"]
  type        = list(string)
}

variable "pe_subnet_name" {
  description = "Specifies the name of the subnet that contains the private endpoints."
  default     = "pe-subnet"
  type        = string
}

variable "pe_subnet_address_prefix" {
  description = "Specifies the address prefix of the subnet that contains the private endpoints."
  default     = ["10.0.1.0/24"]
  type        = list(string)
}

variable "nat_gateway_name" {
  description = "(Required) Specifies the name of the NAT Gateway"
  type        = string
  default     = "NatGateway"
}

variable "nat_gateway_sku_name" {
  description = "(Optional) The SKU which should be used. At this time the only supported value is Standard. Defaults to Standard"
  type        = string
  default     = "Standard"
}

variable "nat_gateway_idle_timeout_in_minutes" {
  description = "(Optional) The idle timeout which should be used in minutes. Defaults to 4."
  type        = number
  default     = 4
}

variable "nat_gateway_zones" {
  description = " (Optional) A list of Availability Zones in which this NAT Gateway should be located. Changing this forces a new NAT Gateway to be created."
  type        = list(string)
  default     = ["1"]
}

variable "website_port" {
  description = "(Optional) Specifies the port on which the Web App will listen. Defaults to 8000."
  type        = number
  default     = 8000
}