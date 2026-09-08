//********************************************
// Parameters
//********************************************
@description('Specifies the name of the virtual network.')
param virtualNetworkName string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the address prefixes of the virtual network.')
param virtualNetworkAddressPrefixes string = '10.0.0.0/8'

@description('Specifies the name of the subnet used by the Web App for the regional virtual network integration.')
param webAppSubnetName string = 'functionAppSubnet'

@description('Specifies the address prefix of the subnet used by the Web App for the regional virtual network integration.')
param webAppSubnetAddressPrefix string = '10.0.0.0/24'

@description('Specifies the name of the network security group associated to the subnet hosting the Web App.')
param webAppSubnetNsgName string = ''

@description('Specifies the name of the subnet which contains the private endpoint to the Azure CosmosDB for MongoDB API account.')
param peSubnetName string = 'pe-subnet'

@description('Specifies the address prefix of the subnet which contains the private endpoint to the Azure CosmosDB for MongoDB API account.')
param peSubnetAddressPrefix string = '10.0.1.0/24'

@description('Specifies the name of the network security group associated to the subnet hosting the private endpoint to the Azure CosmosDB for MongoDB API account.')
param peSubnetNsgName string = ''

@description('Specifies the name of the Azure NAT Gateway.')
param natGatewayName string

@description('Specifies a list of availability zones denoting the zone in which Nat Gateway should be deployed.')
param natGatewayZones array = []

@description('Specifies the name of the public IP prefix for the Azure NAT Gateway.')
param natGatewayPublicIpPrefixName string

@description('Specifies the length of the Public IP Prefix.')
@minValue(28)
@maxValue(32)
param natGatewayPublicIpPrefixLength int = 31

@description('Specifies the idle timeout in minutes for the Azure NAT Gateway.')
param natGatewayIdleTimeoutMins int = 30

@description('Specifies the delegation service name.')
param delegationServiceName string

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************
var diagnosticSettingsName = 'default'
var nsgLogCategories = [
  'NetworkSecurityGroupEvent'
  'NetworkSecurityGroupRuleCounter'
]
var nsgLogs = [for category in nsgLogCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: true
    days: 0
  }
}]
var vnetLogCategories = [
  'VMProtectionAlerts'
]
var vnetMetricCategories = [
  'AllMetrics'
]
var vnetLogs = [for category in vnetLogCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: true
    days: 0
  }
}]
var vnetMetrics = [for category in vnetMetricCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: true
    days: 0
  }
}]

//********************************************
// Resources
//********************************************

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2024-03-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefixes
      ]
    }
    subnets: [
      {
        name: webAppSubnetName
        properties: {
          addressPrefix: webAppSubnetAddressPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
          networkSecurityGroup: {
            id: webAppSubnetNsg.id
          }
          natGateway: {
            id: natGateway.id
          }
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: delegationServiceName
              }
            }
          ]
        }
      }
      {
        name: peSubnetName
        properties: {
          addressPrefix: peSubnetAddressPrefix
          networkSecurityGroup: {
            id: peSubnetNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
          natGateway: {
            id: natGateway.id
          }
        }
      }
    ]
  }
}

resource webAppSubnetNsg 'Microsoft.Network/networkSecurityGroups@2025-05-01' = {
  name: webAppSubnetNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
    ]
  }
}

resource peSubnetNsg 'Microsoft.Network/networkSecurityGroups@2025-05-01' = {
  name: peSubnetNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
    ]
  }
}

// NAT Gateway
resource natGatewayPublicIpPrefix 'Microsoft.Network/publicIPPrefixes@2025-05-01' =  {
  name: natGatewayPublicIpPrefixName
  location: location
  sku: {
    name: 'Standard'
  }
  zones: !empty(natGatewayZones) ? natGatewayZones : []
  properties: {
    publicIPAddressVersion: 'IPv4'
    prefixLength: natGatewayPublicIpPrefixLength
  }
}

resource natGateway 'Microsoft.Network/natGateways@2025-05-01' = {
  name: natGatewayName
  location: location
  sku: {
    name: 'Standard'
  }
  zones: !empty(natGatewayZones) ? natGatewayZones : []
  properties: {
    publicIpPrefixes: [
      {
        id: natGatewayPublicIpPrefix.id
      }
    ]
    idleTimeoutInMinutes: natGatewayIdleTimeoutMins
  }
}

resource peSubnetNsgDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: peSubnetNsg
  properties: {
    workspaceId: workspaceId
    logs: nsgLogs
  }
}

resource webAppSubnetNsgDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: webAppSubnetNsg
  properties: {
    workspaceId: workspaceId
    logs: nsgLogs
  }
}

resource vnetDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: vnet
  properties: {
    workspaceId: workspaceId
    logs: vnetLogs
    metrics: vnetMetrics
  }
}

//********************************************
// Outputs
//********************************************
output virtualNetworkId string = vnet.id
output virtualNetworkName string = vnet.name
output webAppSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, webAppSubnetName)
output webAppSubnetName string = webAppSubnetName
output peSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, peSubnetName)
output peSubnetName string = peSubnetName
