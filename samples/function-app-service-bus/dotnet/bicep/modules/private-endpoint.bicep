//********************************************
// Parameters
//********************************************
@description('Specifies the name of the private endpoint.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the resource ID of the subnet where private endpoints will be created.')
param subnetId string

@description('Specifies the group IDs for the private link service connection.')
param groupIds array 

@description('Specifies the resource ID of the target resource.')
param privateLinkServiceId string

@description('Specifies the resource ID of the private DNS zone.')
param privateDnsZoneId string

@description('Specifies the resource tags.')
param tags object

//********************************************
// Resources
//********************************************

// Private Endpoints
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2025-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: '${name}-pls-connection'
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: groupIds
        }
      }
    ]
    subnet: {
      id: subnetId
    }
  }
}

resource privateDnsZoneGroupName 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2025-05-01' = {
  parent: privateEndpoint
  name: 'private-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'dnsConfig'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

//********************************************
// Outputs
//********************************************
output id string = privateEndpoint.id
output name string = privateEndpoint.name
