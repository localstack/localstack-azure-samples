variable "name" {
  description = "(Required) Specifies the name of the Azure Network Security Group"
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the name of the resource group. of the Azure Network Security Group"
  type        = string
}

variable "location" {
  description = "(Required) Specifies the location of the Azure Network Security Group"
  type        = string
}

variable "security_rules" {
  description = "(Optional) Specifies the security rules of the Azure Network Security Group"
  type = list(object({
    name                                       = string
    priority                                   = number
    direction                                  = string
    access                                     = string
    protocol                                   = string
    source_port_range                          = string
    source_port_ranges                         = list(string)
    destination_port_range                     = string
    destination_port_ranges                    = list(string)
    source_address_prefix                      = string
    source_address_prefixes                    = list(string)
    destination_address_prefix                 = string
    destination_address_prefixes               = list(string)
    source_application_security_group_ids      = list(string)
    destination_application_security_group_ids = list(string)
  }))
  default = []
}

variable "subnet_ids" {
  description = "(Required) A map of subnet ids to associate with the Azure Network Security Group"
  type        = map(string)
}

variable "tags" {
  description = "(Optional) Specifies the tags of the Azure Network Security Group"
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "Specifies the resource id of the Azure Log Analytics workspace"
  type        = string
}
