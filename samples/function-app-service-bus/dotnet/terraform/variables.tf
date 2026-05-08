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

variable "use_dotnet_isolated_runtime" {
  description = "(Optional) Should the DotNet process use an isolated runtime. Defaults to false."
  type        = bool
  default     = true
}

variable "java_version" {
  description = "(Optional) The Version of Java to use."
  type        = string
  default     = null
}

variable "node_version" {
  description = "(Optional) The version of Node.js to run."
  type        = string
  default     = null
}

variable "dotnet_version" {
  description = "(Optional) The version of .NET to use."
  type        = string
  default     = null
}

variable "python_version" {
  description = "(Optional) Specifies the version of Python to run. Possible values include 3.13, 3.12, 3.11, 3.10, 3.9, 3.8 and 3.7."
  type        = string
  default     = null
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
    deployment  = "terraform"
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

variable "func_subnet_name" {
  description = "Specifies the name of the web app subnet."
  default     = "app-subnet"
  type        = string
}

variable "func_subnet_address_prefix" {
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

variable "queue_names" {
  description = "(Optional) Specifies the names of the queues to be created within the Service Bus Namespace."
  type        = set(string)
  default     = ["input", "output"]
}

variable "service_bus_sku" {
  description = "(Required) Specifies the SKU tier for the Service Bus Namespace. Options are Basic, Standard, or Premium."
  type        = string
  default     = "Premium"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.service_bus_sku)
    error_message = "The SKU must be one of Basic, Standard, or Premium."
  }
}

variable "service_bus_capacity" {
  description = "(Optional) Specifies the capacity for the Service Bus Namespace. When SKU is Premium, capacity can be 1, 2, 4, 8, or 16. When SKU is Basic or Standard, capacity can be 0 only."
  type        = number
  default     = 1
}

variable "service_bus_premium_messaging_partitions" {
  description = "(Optional) Specifies the number of messaging partitions. Only valid when SKU is Premium. Possible values include 1, 2, and 4. Defaults to 1."
  type        = number
  default     = 1
}

variable "service_bus_local_auth_enabled" {
  description = "(Optional) Specifies whether SAS authentication is enabled for the Service Bus Namespace. Defaults to true."
  type        = bool
  default     = true
}

variable "service_bus_public_network_access_enabled" {
  description = "(Optional) Specifies whether public network access is enabled for the Service Bus Namespace. Defaults to true."
  type        = bool
  default     = true
}

variable "queue_lock_duration" {
  description = "(Optional) Specifies the ISO 8601 timespan duration of a peek-lock. Maximum value is 5 minutes. Defaults to PT5M."
  type        = string
  default     = "PT5M"
}

variable "queue_max_message_size_in_kilobytes" {
  description = "(Optional) Specifies the maximum size of a message allowed on the queue in kilobytes. Only applicable for Premium SKU."
  type        = number
  default     = null
}

variable "queue_max_size_in_megabytes" {
  description = "(Optional) Specifies the size of memory allocated for the queue in megabytes."
  type        = number
  default     = 1024
}

variable "queue_requires_duplicate_detection" {
  description = "(Optional) Specifies whether the queue requires duplicate detection. Changing this forces a new resource to be created. Defaults to false."
  type        = bool
  default     = false
}

variable "queue_requires_session" {
  description = "(Optional) Specifies whether the queue requires sessions for ordered handling of unbounded sequences of related messages. Changing this forces a new resource to be created. Defaults to false."
  type        = bool
  default     = false
}

variable "queue_default_message_ttl" {
  description = "(Optional) Specifies the ISO 8601 timespan duration of the TTL of messages sent to this queue."
  type        = string
  default     = "P10675199DT2H48M5.4775807S"
}

variable "queue_dead_lettering_on_message_expiration" {
  description = "(Optional) Specifies whether the queue has dead letter support when a message expires. Defaults to false."
  type        = bool
  default     = false
}

variable "queue_duplicate_detection_history_time_window" {
  description = "(Optional) Specifies the ISO 8601 timespan duration during which duplicates can be detected. Defaults to PT10M."
  type        = string
  default     = "PT10M"
}

variable "queue_max_delivery_count" {
  description = "(Optional) Specifies the maximum number of deliveries before a message is automatically dead lettered. Defaults to 10."
  type        = number
  default     = 10
}

variable "queue_status" {
  description = "(Optional) Specifies the status of the queue. Possible values are Active, Creating, Deleting, Disabled, ReceiveDisabled, Renaming, SendDisabled, Unknown. Defaults to Active."
  type        = string
  default     = "Active"
}

variable "queue_batched_operations_enabled" {
  description = "(Optional) Specifies whether server-side batched operations are enabled. Defaults to true."
  type        = bool
  default     = true
}

variable "queue_auto_delete_on_idle" {
  description = "(Optional) Specifies the ISO 8601 timespan duration of the idle interval after which the queue is automatically deleted. Minimum of 5 minutes."
  type        = string
  default     = null
}

variable "queue_partitioning_enabled" {
  description = "(Optional) Specifies whether the queue is partitioned across multiple message brokers. Changing this forces a new resource to be created. Defaults to false."
  type        = bool
  default     = false
}

variable "queue_express_enabled" {
  description = "(Optional) Specifies whether Express Entities are enabled. An express queue holds a message in memory temporarily before writing it to persistent storage. Defaults to false."
  type        = bool
  default     = false
}

variable "queue_forward_to" {
  description = "(Optional) Specifies the name of a queue or topic to automatically forward messages to."
  type        = string
  default     = null
}

variable "queue_forward_dead_lettered_messages_to" {
  description = "(Optional) Specifies the name of a queue or topic to automatically forward dead lettered messages to."
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

variable "functions_worker_runtime" {
  description = "(Required) Specifies the language runtime used by the Azure Functions App."
  type        = string
  default     = "dotnet-isolated"

  validation {
    condition     = contains(["dotnet", "dotnet-isolated", "python", "java", "node", "powerShell", "custom"], var.functions_worker_runtime)
    error_message = "The functions_worker_runtime must be one of: dotnet, dotnet-isolated, python, java, node, powerShell, custom."
  }
}

variable "functions_extension_version" {
  description = "(Optional) Specifies the Azure Functions extension version. Defaults to ~4."
  type        = string
  default     = "~4"
}

variable "input_queue_name" {
  description = "(Optional) Specifies the name of the input queue."
  type        = string
  default     = "input"
}

variable "output_queue_name" {
  description = "(Optional) Specifies the name of the output queue."
  type        = string
  default     = "output"
}

variable "names" {
  description = "(Optional) Specifies a comma-separated list of names to be used as part of the sample data in the Azure Function App."
  type        = string
  default     = "Paolo,John,Jane,Max,Mary,Leo,Mia,Anna,Lisa,Anastasia"
}

variable "timer_schedule" {
  description = "(Optional) Specifies the CRON expression for the timer trigger."
  type        = string
  default     = "*/10 * * * * *"
}

variable "managed_identity_type" {
  description = "(Optional) Specifies the type of managed identity."
  type        = string
  default     = "UserAssigned"

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned"], var.managed_identity_type)
    error_message = "The managed identity type must be either SystemAssigned or UserAssigned."
  }
}
