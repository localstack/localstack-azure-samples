variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location for the Cosmos DB account."
  type        = string
}

variable "name" {
  description = "(Required) Specifies the name of the Cosmos DB account."
  type        = string
}

variable "mongo_server_version" {
  description = "(Optional) Specifies the version of MongoDB API for the Azure Cosmos DB account."
  type        = string
  default     = "7.0"
}

variable "consistency_level" {
  description = "(Required) Specifies the consistency level for the Azure Cosmos DB account."
  type        = string
  default     = "Eventual"
}

variable "primary_region" {
  description = "(Required) Specifies the primary region for the Azure Cosmos DB account."
  type        = string
}

variable "secondary_region" {
  description = "(Required) Specifies the secondary region for the Azure Cosmos DB account."
  type        = string
}

variable "database_name" {
  description = "(Required) Specifies the name of the MongoDB database."
  type        = string
}

variable "database_throughput" {
  description = "(Optional) Specifies the throughput for the MongoDB database."
  type        = number
  default     = 400
}

variable "collection_name" {
  description = "(Required) Specifies the name of the MongoDB collection."
  type        = string
}

variable "collection_throughput" {
  description = "(Optional) Specifies the throughput for the MongoDB collection."
  type        = number
  default     = 400
}

variable "default_ttl_seconds" {
  description = "(Optional) Specifies the default TTL in seconds for documents in the collection."
  type        = string
  default     = "777"
}

variable "shard_key" {
  description = "(Optional) Specifies the shard key for the MongoDB collection."
  type        = string
  default     = "username"
}

variable "index_keys" {
  description = "A list of field names for which to create single-field indexes on the MongoDB collection."
  type        = list(string)
  default     = ["_id"]
}

variable "tags" {
  description = "(Optional) Specifies the tags to be applied to the resources."
  type        = map(any)
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "Specifies the resource id of the Azure Log Analytics workspace."
  type        = string
}

variable "log_analytics_destination_type" {
  description = "(Optional) Specifies where the diagnostic setting writes the logs in the workspace: Dedicated writes them to the resource-specific CDBDataPlaneRequests and CDBMongoRequests tables that Microsoft recommends, AzureDiagnostics to the shared AzureDiagnostics table."
  type        = string
  default     = "Dedicated"

  validation {
    condition     = contains(["AzureDiagnostics", "Dedicated"], var.log_analytics_destination_type)
    error_message = "The log_analytics_destination_type must be AzureDiagnostics or Dedicated."
  }
}
