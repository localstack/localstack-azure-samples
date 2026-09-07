//********************************************
// Parameters
//********************************************
@description('Specifies the name of the private DNS zone.')
param name string

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
  location: 'global'
  tags: tags
}

// Virtual Network Links
resource privateDnsZoneVirtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: 'link-to-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
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
