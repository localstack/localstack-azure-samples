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
param webAppSubnetName string = 'app-subnet'

@description('Specifies the address prefix of the subnet used by the Web App for the regional virtual network integration.')
param webAppSubnetAddressPrefix string = '10.0.0.0/24'

@description('Specifies the name of the network security group associated to the subnet hosting the Web App.')
param webAppSubnetNsgName string = ''

@description('Specifies the name of the subnet that hosts the private endpoint to the PostgreSQL flexible server.')
param peSubnetName string = 'pe-subnet'

@description('Specifies the address prefix of the subnet that hosts the private endpoint to the PostgreSQL flexible server.')
param peSubnetAddressPrefix string = '10.0.1.0/24'

@description('Specifies the name of the network security group associated with the private-endpoint subnet.')
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

@description('Specifies the name of the delegation of the Web App subnet.')
param delegationName string = 'delegation'

@description('Specifies the private endpoint network policies of the subnets.')
@allowed([
  'Disabled'
  'Enabled'
  'NetworkSecurityGroupEnabled'
  'RouteTableEnabled'
])
param subnetPrivateEndpointNetworkPolicies string = 'Disabled'

@description('Specifies the private link service network policies of the subnets.')
@allowed([
  'Disabled'
  'Enabled'
])
param subnetPrivateLinkServiceNetworkPolicies string = 'Disabled'

@description('Specifies the security rules of the network security group of the Web App subnet.')
param webAppSubnetNsgSecurityRules array = []

@description('Specifies the security rules of the network security group of the private-endpoint subnet.')
param peSubnetNsgSecurityRules array = []

@description('Specifies the SKU of the Azure NAT Gateway and of its public IP prefix.')
@allowed([
  'Standard'
  'StandardV2'
])
param natGatewaySkuName string = 'Standard'

@description('Specifies the IP version of the public IP prefix of the Azure NAT Gateway.')
@allowed([
  'IPv4'
  'IPv6'
])
param publicIpAddressVersion string = 'IPv4'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories enabled by the diagnostic settings of the network security groups.')
param nsgLogCategories array = [
  'NetworkSecurityGroupEvent'
  'NetworkSecurityGroupRuleCounter'
]

@description('Specifies the log categories enabled by the diagnostic settings of the virtual network.')
param vnetLogCategories array = [
  'VMProtectionAlerts'
]

@description('Specifies the metric categories enabled by the diagnostic settings of the virtual network.')
param vnetMetricCategories array = [
  'AllMetrics'
]

@description('Specifies whether the retention policy of the diagnostic settings is enabled.')
param retentionPolicyEnabled bool = true

@description('Specifies the retention of the diagnostic settings in days (0 keeps the data as long as the workspace does).')
param retentionPolicyDays int = 0

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************
var nsgLogs = [for category in nsgLogCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: retentionPolicyEnabled
    days: retentionPolicyDays
  }
}]
var vnetLogs = [for category in vnetLogCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: retentionPolicyEnabled
    days: retentionPolicyDays
  }
}]
var vnetMetrics = [for category in vnetMetricCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: retentionPolicyEnabled
    days: retentionPolicyDays
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
          privateEndpointNetworkPolicies: subnetPrivateEndpointNetworkPolicies
          privateLinkServiceNetworkPolicies: subnetPrivateLinkServiceNetworkPolicies
          networkSecurityGroup: {
            id: webAppSubnetNsg.id
          }
          natGateway: {
            id: natGateway.id
          }
          delegations: [
            {
              name: delegationName
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
          privateEndpointNetworkPolicies: subnetPrivateEndpointNetworkPolicies
          privateLinkServiceNetworkPolicies: subnetPrivateLinkServiceNetworkPolicies
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
    securityRules: webAppSubnetNsgSecurityRules
  }
}

resource peSubnetNsg 'Microsoft.Network/networkSecurityGroups@2025-05-01' = {
  name: peSubnetNsgName
  location: location
  tags: tags
  properties: {
    securityRules: peSubnetNsgSecurityRules
  }
}

// NAT Gateway
resource natGatewayPublicIpPrefix 'Microsoft.Network/publicIPPrefixes@2025-05-01' =  {
  name: natGatewayPublicIpPrefixName
  location: location
  sku: {
    name: natGatewaySkuName
  }
  zones: !empty(natGatewayZones) ? natGatewayZones : []
  properties: {
    publicIPAddressVersion: publicIpAddressVersion
    prefixLength: natGatewayPublicIpPrefixLength
  }
}

resource natGateway 'Microsoft.Network/natGateways@2025-05-01' = {
  name: natGatewayName
  location: location
  sku: {
    name: natGatewaySkuName
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
