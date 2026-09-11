variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group."
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the Azure NAT Gateway"
  type        = string
}

variable "name" {
  description = "(Required) Specifies the name of the Azure NAT Gateway"
  type        = string
}

variable "tags" {
  description = "(Optional) Specifies the tags of the Azure NAT Gateway"
  type        = map(any)
  default     = {}
}

variable "sku_name" {
  description = "(Optional) The SKU which should be used. At this time the only supported value is Standard. Defaults to Standard"
  type        = string
  default     = "Standard"
}

variable "idle_timeout_in_minutes" {
  description = "(Optional) The idle timeout which should be used in minutes. Defaults to 4."
  type        = number
  default     = 4
}

variable "zones" {
  description = " (Optional) A list of Availability Zones in which this NAT Gateway should be located. Changing this forces a new NAT Gateway to be created."
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "(Required) A map of subnet ids to associate with the NAT Gateway"
  type        = map(string)
}

variable "public_ip_name" {
  description = "(Optional) Specifies the name of the public IP address of the NAT Gateway. Defaults to the NAT Gateway name followed by PublicIp."
  type        = string
  default     = null
}

variable "public_ip_allocation_method" {
  description = "(Optional) Specifies the allocation method of the public IP address: Static or Dynamic. A NAT Gateway requires Static. Defaults to Static."
  type        = string
  default     = "Static"

  validation {
    condition     = contains(["Static", "Dynamic"], var.public_ip_allocation_method)
    error_message = "The public_ip_allocation_method must be Static or Dynamic."
  }
}

variable "public_ip_sku" {
  description = "(Optional) Specifies the SKU of the public IP address: Basic or Standard. A NAT Gateway requires Standard. Defaults to Standard."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard"], var.public_ip_sku)
    error_message = "The public_ip_sku must be Basic or Standard."
  }
}
