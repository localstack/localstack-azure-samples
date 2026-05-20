variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group. of the Azure Storage Account"
  type        = string
}

variable "name" {
  description = "(Required) Specifies the name of the Azure Storage Account"
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the Azure Storage Account"
  type        = string
}

variable "account_kind" {
  description = "(Optional) Specifies the account kind of the Azure Storage Account"
  default     = "StorageV2"
  type        = string

  validation {
    condition     = contains(["Storage", "StorageV2"], var.account_kind)
    error_message = "The account kind of the Azure Storage Account is invalid."
  }
}

variable "account_tier" {
  description = "(Optional) Specifies the account tier of the Azure Storage Account"
  default     = "Standard"
  type        = string

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "The account tier of the Azure Storage Account is invalid."
  }
}

variable "replication_type" {
  description = "(Optional) Specifies the replication type of the Azure Storage Account"
  default     = "LRS"
  type        = string

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RA-GRS", "RA-GZRS"], var.replication_type)
    error_message = "The replication type of the Azure Storage Account is invalid."
  }
}

variable "is_hns_enabled" {
  description = "(Optional) Specifies the replication type of the Azure Storage Account"
  default     = false
  type        = bool
}

variable "default_action" {
  description = "Allow or disallow public access to all blobs or containers in the Azure Storage Accounts. The default interpretation is true for this property."
  default     = "Allow"
  type        = string
}

variable "ip_rules" {
  description = "Specifies IP rules for the Azure Storage Account"
  default     = []
  type        = list(string)
}

variable "virtual_network_subnet_ids" {
  description = "Specifies a list of resource ids for subnets"
  default     = []
  type        = list(string)
}

variable "kind" {
  description = "(Optional) Specifies the kind of the Azure Storage Account"
  default     = ""
}

variable "bypass" {
  description = " (Optional) Specifies whether traffic is bypassed for Logging/Metrics/AzureServices. Valid options are any combination of Logging, Metrics, AzureServices, or None."
  default     = ["Logging", "Metrics", "AzureServices"]
  type        = set(string)
}

variable "shared_access_key_enabled" {
  description = "(Optional) Indicates whether the storage account permits requests to be authorized with the account access key via Shared Key. If false, then all requests, including shared access signatures, must be authorized with Azure Active Directory (Azure AD). Defaults to true."
  default     = true
  type        = bool
}

variable "access_tier" {
  description = "(Optional) Specifies the access tier of the storage account. The default value is Hot."
  type        = string
  default     = "Hot"
}

variable "min_tls_version" {
  description = "(Optional) Specifies the minimum TLS version to be permitted on requests to storage. The default value is TLS1_2."
  type        = string
  default     = "TLS1_2"
}

variable "https_traffic_only_enabled" {
  description = "(Optional) Specifies whether the storage account should only support HTTPS traffic."
  type        = bool
  default     = true
}

variable "allow_blob_public_access" {
  description = "(Optional) Specifies whether the storage account allows public access to blobs."
  type        = bool
  default     = true
}

variable "cross_tenant_replication_enabled" {
  description = "(Optional) Specifies whether the storage account allows cross-tenant replication."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "(Optional) Specifies whether public network access is enabled for the storage account."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Specifies the resource id of the Azure Log Analytics workspace."
  type        = string
}

variable "tags" {
  description = "(Optional) Specifies the tags of the Azure Storage Account"
  default     = {}
}
