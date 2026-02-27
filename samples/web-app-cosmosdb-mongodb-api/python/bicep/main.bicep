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

@description('Specifies the language runtime used by the Azure Web App.')
@allowed([
  'dotnet'
  'dotnet-isolated'
  'python'
  'java'
  'node'
  'powerShell'
  'custom'
])
param runtimeName string

@description('Specifies the target language version used by the Azure Web App.')
param runtimeVersion string

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

@description('Specifies the primary replica region for the Cosmos DB account.')
param primaryRegion string = 'westeurope'

@description('Specifies the secondary replica region for the Cosmos DB account.')
param secondaryRegion string = 'northeurope'

@allowed([
  'Eventual'
  'ConsistentPrefix'
  'Session'
  'BoundedStaleness'
  'Strong'
])
@description('Specifies the default consistency level of the Cosmos DB account.')
param defaultConsistencyLevel string = 'Eventual'

@allowed([
  '3.2'
  '3.6'
  '4.0'
  '4.2'
  '5.0'
  '6.0'
  '7.0'
  '8.0'
])


@description('Specifies the Cosmos DB server version to use.')
param serverVersion string = '7.0'

@minValue(10)
@maxValue(2147483647)
@description('Specifies the max stale requests. Required for BoundedStaleness. Valid ranges, Single Region: 10 to 2147483647. Multi Region: 100000 to 2147483647.')
param maxStalenessPrefix int = 100000

@minValue(5)
@maxValue(86400)
@description('Specifies the max lag time (seconds). Required for BoundedStaleness. Valid ranges, Single Region: 5 to 84600. Multi Region: 300 to 86400.')
param maxIntervalInSeconds int = 300

@description('Specifies the name for the Mongo DB database.')
param databaseName string = 'sampledb'

@minValue(400)
@maxValue(1000000)
@description('Specifies the shared throughput for the Mongo DB database, up to 25 collections.')
param sharedThroughput int = 400

@description('Specifies the name for the Mongo DB collection.')
param collectionName string = 'activities'

@minValue(400)
@maxValue(1000000)
@description('Specifies the dedicated throughput for the Mongo DB collection.')
param dedicatedThroughput int = 400

@description('Specifies a list of field names for which to create single-field indexes on the MongoDB collection.')
param mongoDbIndexKeys array = ['_id','username', 'activity', 'timestamp']

@description('Specifies the username for the application.')
param username string = 'paolo'

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

@description('Specifies the name of the private endpoint to the Azure CosmosDB for MongoDB API account.')
param cosmosDbPrivateEndpointName string = ''

@description('Specifies the name of the Azure Log Analytics resource.')
param logAnalyticsName string = ''

@description('Specifies the service tier of the workspace: Free, Standalone, PerNode, Per-GB.')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
param logAnalyticsSku string = 'PerNode'

@description('Specifies the workspace data retention in days. -1 means Unlimited retention for the Unlimited Sku. 730 days is the maximum allowed for all other Skus.')
param logAnalyticsRetentionInDays int = 60

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
var accountName = '${prefix}-mongodb-${suffix}'

//********************************************
// Modules and Resources
//********************************************
module workspace 'modules/log-analytics.bicep' = {
  name: 'workspace'
  params: {
    // properties
    name: empty(logAnalyticsName) ? toLower('${prefix}-log-analytics-${suffix}') : logAnalyticsName
    location: location
    tags: tags
    sku: logAnalyticsSku
    retentionInDays: logAnalyticsRetentionInDays
  }
}

module mongoDb 'modules/mongo-db.bicep' = {
  name: 'mongoDb'
  params: {
    name: accountName
    location: location
    primaryRegion: primaryRegion
    secondaryRegion: secondaryRegion
    defaultConsistencyLevel: defaultConsistencyLevel
    serverVersion: serverVersion
    maxStalenessPrefix: maxStalenessPrefix
    maxIntervalInSeconds: maxIntervalInSeconds
    databaseName: databaseName
    sharedThroughput: sharedThroughput
    collectionName: collectionName
    dedicatedThroughput: dedicatedThroughput
    mongoDbIndexKeys: mongoDbIndexKeys
    workspaceId: workspace.outputs.id
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
    workspaceId: workspace.outputs.id
    location: location
    tags: tags
  }
}

module privateDnsZone 'modules/private-dns-zone.bicep' = {
  name: 'privateDnsZone'
  params: {
    name: 'privatelink.mongo.cosmos.azure.com'
    vnetId: network.outputs.virtualNetworkId
    tags: tags
  }
}

module privateEndpoints 'modules/private-endpoint.bicep' = {
  name: 'privateEndpoints'
  params: {
    name: empty(cosmosDbPrivateEndpointName)
      ? toLower('${prefix}-mongodb-pe-${suffix}')
      : cosmosDbPrivateEndpointName
    privateLinkServiceId: mongoDb.outputs.id
    privateDnsZoneId: privateDnsZone.outputs.id
    vnetId: network.outputs.virtualNetworkId
    subnetId: network.outputs.peSubnetId
    groupIds: [
      'mongodb'
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
    workspaceId: workspace.outputs.id
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
    runtimeName: runtimeName
    runtimeVersion: runtimeVersion
    minTlsVersion: minTlsVersion
    publicNetworkAccess: publicNetworkAccess
    repoUrl: repoUrl
    virtualNetworkName: network.outputs.virtualNetworkName
    subnetName: network.outputs.webAppSubnetName
    hostingPlanName: appServicePlan.outputs.name
    accountName: mongoDb.outputs.name
    databaseName: mongoDb.outputs.databaseName
    collectionName: mongoDb.outputs.collectionName
    username: username
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

//********************************************
// Outputs
//********************************************
output webAppName string = webApp.outputs.name
output accountName string = mongoDb.outputs.name
output databaseName string = mongoDb.outputs.databaseName
output collectionName string = collectionName
output documentEndpoint string = mongoDb.outputs.documentEndpoint
