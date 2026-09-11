variable "name" {
  description = "(Required) Specifies the name of the Azure Private DNS Zone"
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group. of the Azure Private DNS Zone"
  type        = string
}

variable "tags" {
  description = "(Optional) Specifies the tags of the Azure Private DNS Zone"
  default     = {}
}

variable "virtual_networks_to_link" {
  description = "(Optional) Specifies the subscription id, resource group name, and name of the virtual networks to which create a virtual network link"
  type        = map(any)
  default     = {}
}

variable "virtual_network_link_name" {
  description = "(Optional) Specifies the name of the virtual network links. Defaults to link-to-vnet, the name the Azure CLI and Bicep variants of the samples use, so the three provisioning modes produce the same topology."
  type        = string
  default     = "link-to-vnet"
}

variable "registration_enabled" {
  description = "(Optional) Specifies whether auto-registration of virtual machine records in the zone is enabled for the linked virtual networks. Defaults to false."
  type        = bool
  default     = false
}
