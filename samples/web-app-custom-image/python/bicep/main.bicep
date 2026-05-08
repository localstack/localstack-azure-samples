//********************************************
// Parameters
//********************************************
@description('Specifies the prefix for the name of the Azure resources.')
@minLength(2)
param prefix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the suffix for the name of the Azure resources.')
@minLength(2)
param suffix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('Specifies the name of the image to be used for the Web App.')
param imageName string

@description('Specifies the tag of the image to be used for the Web App.')
param imageTag string

@description('Specifies the tier name for the hosting plan.')
@allowed([
  'Basic'
  'Standard'
  'ElasticPremium'
  'Premium'
  'PremiumV2'
  'Premium0V3'
  'PremiumV3'
  'PremiumMV3'
  'Isolated'
  'IsolatedV2'
  'WorkflowStandard'
  'FlexConsumption'
])
param skuTier string = 'Standard'

@description('Specifies the SKU name for the hosting plan.')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'EP1'
  'EP2'
  'EP3'
  'P1'
  'P2'
  'P3'
  'P1V2'
  'P2V2'
  'P3V2'
  'P0V3'
  'P1V3'
  'P2V3'
  'P3V3'
  'P1MV3'
  'P2MV3'
  'P3MV3'
  'P4MV3'
  'P5MV3'
  'I1'
  'I2'
  'I3'
  'I1V2'
  'I2V2'
  'I3V2'
  'I4V2'
  'I5V2'
  'I6V2'
  'WS1'
  'WS2'
  'WS3'
  'FC1'
])
param skuName string = 'S1'

@description('Specifies the kind of the hosting plan.')
@allowed([
  'app'
  'elastic'
  'functionapp'
  'windows'
  'linux'
])
param appServicePlanKind string = 'linux'

@description('Specifies whether the hosting plan is reserved.')
param reserved bool = true

@description('Specifies whether the hosting plan is zone redundant.')
param zoneRedundant bool = false

@description('Specifies the kind of the hosting plan.')
@allowed([
  'app'                                    // Windows Web app
  'app,linux'                              // Linux Web app
  'app,linux,container'                    // Linux Container Web app
  'hyperV'                                 // Windows Container Web App
  'app,container,windows'                  // Windows Container Web App
  'app,linux,kubernetes'                   // Linux Web App on ARC
  'app,linux,container,kubernetes'         // Linux Container Web App on ARC
  'functionapp'                            // Function Code App
  'functionapp,linux'                      // Linux Consumption Function app
  'functionapp,linux,container,kubernetes' // Function Container App on ARC
  'functionapp,linux,kubernetes'           // Function Code App on ARC
])
param webAppKind string = 'app,linux'

@description('Specifies whether HTTPS is enforced for the Azure Web App.')
param httpsOnly bool = false

@description('Specifies the minimum TLS version for the Azure Web App.')
@allowed([
  '1.2'
  '1.3'
])
param minTlsVersion string = '1.2'

@description('Specifies whether the public network access is enabled or disabled')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Specifies the optional Git Repo URL.')
param repoUrl string = ' '

@description('Specifies the name of the virtual network.')
param virtualNetworkName string = ''

@description('Specifies the address prefixes of the virtual network.')
param virtualNetworkAddressPrefixes string = '10.0.0.0/8'

@description('Specifies the name of the subnet used by the Web App for the regional virtual network integration.')
param webAppSubnetName string = 'app-subnet'

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

@description('Specifies the length of the Public IP Prefix.')
@minValue(28)
@maxValue(32)
param natGatewayPublicIpPrefixLength int = 31

@description('Specifies the name of the Azure NAT Gateway.')
param natGatewayName string = ''

@description('Specifies a list of availability zones denoting the zone in which Nat Gateway should be deployed.')
param natGatewayZones array = []

@description('Specifies the idle timeout in minutes for the Azure NAT Gateway.')
param natGatewayIdleTimeoutMins int = 30

@description('Specifies the name of the Azure Container Registry resource.')
param acrName string = ''

@description('Specifies the name of the Azure Log Analytics resource.')
param logAnalyticsWorkspaceName string = ''

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

//********************************************
// Variables
//********************************************
var webAppName = '${prefix}-webapp-${suffix}'
var appServicePlanName = '${prefix}-app-service-plan-${suffix}'
var managedIdentityName = '${prefix}-identity-${suffix}'
var privateDnsZoneName = 'privatelink.azurecr.io'
var privateEndpointName = '${prefix}-acr-pe-${suffix}'

//********************************************
// Modules and Resources
//********************************************
resource workspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' existing = {
  name: logAnalyticsWorkspaceName == '' ? toLower('${prefix}-log-analytics-${suffix}') : logAnalyticsWorkspaceName
}
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2024-11-01-preview' existing = {
  name: acrName == '' ? toLower('${prefix}acr${suffix}') : acrName
}

module managedIdentity 'modules/managed-identity.bicep' = {
  name: 'managedIdentity'
  params: {
    // properties
    name: managedIdentityName
    containerRegistryName: containerRegistry.name
    location: location
    tags: tags
  }
}

module network 'modules/virtual-network.bicep' = {
  name: 'network'
  params: {
    virtualNetworkName: empty(virtualNetworkName) ? toLower('${prefix}-vnet-${suffix}') : virtualNetworkName
    virtualNetworkAddressPrefixes: virtualNetworkAddressPrefixes
    webAppSubnetName: webAppSubnetName
    webAppSubnetAddressPrefix: webAppSubnetAddressPrefix
    webAppSubnetNsgName: empty(webAppSubnetNsgName) ? toLower('${prefix}-webapp-subnet-nsg-${suffix}') : webAppSubnetNsgName
    peSubnetName: peSubnetName
    peSubnetAddressPrefix: peSubnetAddressPrefix
    peSubnetNsgName: empty(peSubnetNsgName) ? toLower('${prefix}-pe-subnet-nsg-${suffix}') : peSubnetNsgName
    natGatewayName: empty(natGatewayName) ? toLower('${prefix}-nat-gateway-${suffix}') : natGatewayName
    natGatewayZones: natGatewayZones
    natGatewayPublicIpPrefixName: toLower('${prefix}-nat-gateway-pip-prefix-${suffix}')
    natGatewayPublicIpPrefixLength: natGatewayPublicIpPrefixLength
    natGatewayIdleTimeoutMins: natGatewayIdleTimeoutMins
    delegationServiceName: skuTier == 'FlexConsumption' ? 'Microsoft.App/environments' : 'Microsoft.Web/serverfarms'
    workspaceId: workspace.id
    location: location
    tags: tags
  }
}

module privateDnsZone 'modules/private-dns-zone.bicep' = {
  name: 'privateDnsZone'
  params: {
    name: privateDnsZoneName
    vnetId: network.outputs.virtualNetworkId
    tags: tags
  }
}

module privateEndpoints 'modules/private-endpoint.bicep' = {
  name: 'privateEndpoints'
  params: {
    name: privateEndpointName
    privateLinkServiceId: containerRegistry.id
    privateDnsZoneId: privateDnsZone.outputs.id
    vnetId: network.outputs.virtualNetworkId
    subnetId: network.outputs.peSubnetId
    groupIds: [
      'registry'
    ]
    location: location
    tags: tags
  }
}

module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'appServicePlan'
  params: {
    name: appServicePlanName
    location: location
    skuName: skuName
    skuTier: skuTier
    kind: appServicePlanKind
    reserved: reserved
    zoneRedundant: zoneRedundant
    workspaceId: workspace.id
    tags: tags
  }
}

module webApp 'modules/web-app.bicep' = {
  name: webAppName
  params: {
    name: webAppName
    location: location
    kind: webAppKind
    httpsOnly: httpsOnly
    minTlsVersion: minTlsVersion
    publicNetworkAccess: publicNetworkAccess
    repoUrl: repoUrl
    virtualNetworkName: network.outputs.virtualNetworkName
    subnetName: network.outputs.webAppSubnetName
    hostingPlanName: appServicePlan.outputs.name
    loginServer: containerRegistry.properties.loginServer
    imageName: imageName
    imageTag: imageTag
    managedIdentityName: managedIdentity.outputs.name
    managedIdentityType: 'UserAssigned'
    workspaceId: workspace.id
    tags: tags
  }
}

//********************************************
// Outputs
//********************************************
output appServicePlanName string = appServicePlan.outputs.name
output webAppName string = webApp.outputs.name
output acrName string = containerRegistry.name
output acrLoginServer string = containerRegistry.properties.loginServer
output managedIdentityName string = managedIdentity.outputs.name
