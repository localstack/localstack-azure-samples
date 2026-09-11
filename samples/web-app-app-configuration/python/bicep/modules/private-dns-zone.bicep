//********************************************
// Parameters
//********************************************
@description('Specifies the name of the private DNS zone.')
param name string

@description('Specifies the location of the private DNS zone and of its virtual network links: private DNS zones are global.')
param location string = 'global'

@description('Specifies the name of the virtual network link: link-to-vnet, the name the Azure CLI and Terraform variants use, so the three provisioning modes produce the same topology.')
param virtualNetworkLinkName string = 'link-to-vnet'

@description('Specifies whether auto-registration of virtual machine records in the zone is enabled for the linked virtual network.')
param registrationEnabled bool = false

@description('Specifies the resource ID of the virtual network where private endpoints will be created.')
param vnetId string

@description('Specifies the resource tags.')
param tags object

//********************************************
// Resources
//********************************************

// Private DNS Zones
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: name
  location: location
  tags: tags
}

// Virtual Network Links
resource privateDnsZoneVirtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: virtualNetworkLinkName
  location: location
  properties: {
    registrationEnabled: registrationEnabled
    virtualNetwork: {
      id: vnetId
    }
  }
}

//********************************************
// Outputs
//********************************************
output id string = privateDnsZone.id
output name string = privateDnsZone.name
