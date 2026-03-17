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

@description('Specifies the language runtime used by the Azure Functions App.')
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

@description('Specifies the target language version used by the Azure Functions App.')
param runtimeVersion string

@description('Specifies the kind of the hosting plan.')
@allowed([
  'app' // Windows Web app
  'app,linux' // Linux Web app
  'app,linux,container' // Linux Container Web app
  'hyperV' // Windows Container Web App
  'app,container,windows' // Windows Container Web App
  'app,linux,kubernetes' // Linux Web App on ARC
  'app,linux,container,kubernetes' // Linux Container Web App on ARC
  'functionapp' // Function Code App
  'functionapp,linux' // Linux Consumption Function app
  'functionapp,linux,container,kubernetes' // Function Container App on ARC
  'functionapp,linux,kubernetes' // Function Code App on ARC
])
param functionAppKind string = 'functionapp,linux'

@description('Specifies whether HTTPS is enforced for the Azure Functions App.')
param httpsOnly bool = false

@description('Specifies the minimum TLS version for the Azure Functions App.')
@allowed([
  '1.0'
  '1.1'
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

@description('Specifies whether Always On is enabled for the Azure Functions App.')
param alwaysOn bool = true

@description('Specifies the optional Git Repo URL.')
param repoUrl string = ''

@description('Enabling this property creates a Premium Service Bus Namespace in regions supported availability zones.')
param serviceBusNamespaceZoneRedundant bool = true

@description('Specifies the messaging units for the Service Bus namespace. For Premium tier, capacity are 1,2 and 4.')
param serviceBusNamespaceCapacity int = 1

@description('Specifies the name of Service Bus namespace SKU.')
@allowed([
  'Basic'
  'Premium'
  'Standard'
])
param serviceBusSkuName string = 'Premium'

@description('Specifies a list of queue names.')
param queueNames array = [
  'input'
  'output'
]

@description('Specifies the name of the virtual network.')
param virtualNetworkName string = ''

@description('Specifies the address prefixes of the virtual network.')
param virtualNetworkAddressPrefixes string = '10.0.0.0/8'

@description('Specifies the name of the subnet used by the Azure Functions App for the regional virtual network integration.')
param functionAppSubnetName string = 'func-subnet'

@description('Specifies the address prefix of the subnet used by the Azure Functions App for the regional virtual network integration.')
param functionAppSubnetAddressPrefix string = '10.0.0.0/24'

@description('Specifies the name of the network security group associated to the subnet hosting the Azure Functions App.')
param functionAppSubnetNsgName string = ''

@description('Specifies the name of the subnet which contains the private endpoint to the Service Bus namespace.')
param peSubnetName string = 'pe-subnet'

@description('Specifies the address prefix of the subnet which contains the private endpoint to the Service Bus namespace.')
param peSubnetAddressPrefix string = '10.0.1.0/24'

@description('Specifies the name of the network security group associated to the subnet hosting the private endpoint to the Service Bus namespace.')
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

@description('Specifies whether to allow public network access for the storage account.')
@allowed([
  'Disabled'
  'Enabled'
])
param storageAccountPublicNetworkAccess string = 'Enabled'

@description('Specifies the access tier of the Azure Storage Account resource. The default value is Hot.')
param storageAccountAccessTier string = 'Hot'

@description('Specifies whether the Azure Storage Account resource allows public access to blobs.')
param storageAccountAllowBlobPublicAccess bool = true

@description('Specifies whether the Azure Storage Account resource allows shared key access.')
param storageAccountAllowSharedKeyAccess bool = true

@description('Specifies whether the Azure Storage Account resource allows cross-tenant replication.')
param storageAccountAllowCrossTenantReplication bool = false

@description('Specifies the minimum TLS version to be permitted on requests to the Azure Storage Account resource. The default value is TLS1_2.')
param storageAccountMinimumTlsVersion string = 'TLS1_2'

@description('The default action of allow or deny when no other rules match. Allowed values: Allow or Deny')
@allowed([
  'Allow'
  'Deny'
])
param storageAccountANetworkAclsDefaultAction string = 'Allow'

@description('Specifies whether the Azure Storage Account resource should only support HTTPS traffic.')
param storageAccountSupportsHttpsTrafficOnly bool = true

@description('Specifies whether to create containers.')
param storageAccountCreateContainers bool = false

@description('Specifies an array of containers to create.')
param storageAccountContainerNames array = []

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

@description('Specifies the type of managed identity.')
@allowed([
  'SystemAssigned'
  'UserAssigned'
])
param managedIdentityType string = 'UserAssigned'

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  deployment: 'bicep'
}

@description('Specifies a list of names to be used as part of the sample data in the Azure Function App.')
param names string = 'Paolo,John,Jane,Max,Mary,Leo,Mia,Anna,Lisa,Anastasia'

//********************************************
// Variables
//********************************************
var functionAppName = '${prefix}-func-${suffix}'
var appServicePlanName = '${prefix}-plan-${suffix}'
var serviceBusNamespaceName = '${prefix}-service-bus-${suffix}'
var storageAccountName = '${prefix}storage${suffix}'
var managedIdentityName = '${prefix}-identity-${suffix}'
var blobStoragePrivateEndpointName = '${prefix}-blob-storage-pe-${suffix}'
var queueStoragePrivateEndpointName = '${prefix}-queue-storage-pe-${suffix}'
var tableStoragePrivateEndpointName = '${prefix}-table-storage-pe-${suffix}'
var serviceBusPrivateEndpointName = '${prefix}-service-bus-pe-${suffix}'

//********************************************
// Modules and Resources
//********************************************
module applicationInsights 'modules/application-insights.bicep' = {
  name: 'applicationInsights'
  params: {
    // properties
    name: functionAppName
    location: location
    tags: tags
    workspaceId: workspace.outputs.id
  }
}

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

module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccount'
  params: {
    // properties
    name: storageAccountName
    location: location
    tags: tags
    publicNetworkAccess: storageAccountPublicNetworkAccess
    accessTier: storageAccountAccessTier
    allowBlobPublicAccess: storageAccountAllowBlobPublicAccess
    allowSharedKeyAccess: storageAccountAllowSharedKeyAccess
    allowCrossTenantReplication: storageAccountAllowCrossTenantReplication
    minimumTlsVersion: storageAccountMinimumTlsVersion
    networkAclsDefaultAction: storageAccountANetworkAclsDefaultAction
    supportsHttpsTrafficOnly: storageAccountSupportsHttpsTrafficOnly
    workspaceId: workspace.outputs.id
    createContainers: storageAccountCreateContainers
    containerNames: storageAccountContainerNames
    createFileShares: false
    fileShareNames: []
  }
}

module serviceBus 'modules/service-bus.bicep' = {
  name: 'serviceBus'
  params: {
    name: serviceBusNamespaceName
    location: location
    capacity: serviceBusNamespaceCapacity
    skuName: serviceBusSkuName
    zoneRedundant: serviceBusNamespaceZoneRedundant
    workspaceId: workspace.outputs.id
    queueNames: queueNames
    tags: tags
  }
}

module network 'modules/virtual-network.bicep' = {
  name: 'network'
  params: {
    virtualNetworkName: empty(virtualNetworkName) ? toLower('${prefix}-vnet-${suffix}') : virtualNetworkName
    virtualNetworkAddressPrefixes: virtualNetworkAddressPrefixes
    functionAppSubnetName: functionAppSubnetName
    functionAppSubnetAddressPrefix: functionAppSubnetAddressPrefix
    functionAppSubnetNsgName: empty(functionAppSubnetNsgName)
      ? toLower('${prefix}-webapp-subnet-nsg-${suffix}')
      : functionAppSubnetNsgName
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

module blobStoragePrivateDnsZone 'modules/private-dns-zone.bicep' = {
  name: 'blobStoragePrivateDnsZone'
  params: {
    name: 'privatelink.blob.core.windows.net'
    vnetId: network.outputs.virtualNetworkId
    tags: tags
  }
}

module blobStoragePrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'blobStoragePrivateEndpoint'
  params: {
    name: blobStoragePrivateEndpointName
    privateLinkServiceId: storageAccount.outputs.id
    privateDnsZoneId: blobStoragePrivateDnsZone.outputs.id
    subnetId: network.outputs.peSubnetId
    groupIds: [
      'blob'
    ]
    location: location
    tags: tags
  }
}

module queueStoragePrivateDnsZone 'modules/private-dns-zone.bicep' = {
  name: 'queueStoragePrivateDnsZone'
  params: {
    name: 'privatelink.queue.core.windows.net'
    vnetId: network.outputs.virtualNetworkId
    tags: tags
  }
}

module queueStoragePrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'queueStoragePrivateEndpoint'
  params: {
    name: queueStoragePrivateEndpointName
    privateLinkServiceId: storageAccount.outputs.id
    privateDnsZoneId: queueStoragePrivateDnsZone.outputs.id
    subnetId: network.outputs.peSubnetId
    groupIds: [
      'queue'
    ]
    location: location
    tags: tags
  }
}

module tableStoragePrivateDnsZone 'modules/private-dns-zone.bicep' = {
  name: 'tableStoragePrivateDnsZone'
  params: {
    name: 'privatelink.table.core.windows.net'
    vnetId: network.outputs.virtualNetworkId
    tags: tags
  }
}

module tableStoragePrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'tableStoragePrivateEndpoint'
  params: {
    name: tableStoragePrivateEndpointName
    privateLinkServiceId: storageAccount.outputs.id
    privateDnsZoneId: tableStoragePrivateDnsZone.outputs.id
    subnetId: network.outputs.peSubnetId
    groupIds: [
      'table'
    ]
    location: location
    tags: tags
  }
}

module serviceBusPrivateDnsZone 'modules/private-dns-zone.bicep' = {
  name: 'serviceBusPrivateDnsZone'
  params: {
    name: 'privatelink.servicebus.windows.net'
    vnetId: network.outputs.virtualNetworkId
    tags: tags
  }
}

module serviceBusPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'serviceBusPrivateEndpoint'
  params: {
    name: serviceBusPrivateEndpointName
    privateLinkServiceId: serviceBus.outputs.id
    privateDnsZoneId: serviceBusPrivateDnsZone.outputs.id
    subnetId: network.outputs.peSubnetId
    groupIds: [
      'namespace'
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

module managedIdentity 'modules/managed-identity.bicep' = if (managedIdentityType == 'UserAssigned') {
  name: 'managedIdentity'
  params: {
    // properties
    name: managedIdentityName
    storageAccountName: storageAccount.outputs.name
    applicationInsightsName: applicationInsights.outputs.name
    serviceBusName: serviceBus.outputs.name
    location: location
    tags: tags
  }
}

module functionApp 'modules/function-app.bicep' = {
  name: functionAppName
  params: {
    name: functionAppName
    location: location
    kind: functionAppKind
    httpsOnly: httpsOnly
    runtimeName: runtimeName
    runtimeVersion: runtimeVersion
    alwaysOn: alwaysOn
    minTlsVersion: minTlsVersion
    publicNetworkAccess: publicNetworkAccess
    repoUrl: repoUrl
    virtualNetworkName: network.outputs.virtualNetworkName
    subnetName: network.outputs.functionAppSubnetName
    hostingPlanName: appServicePlan.outputs.name
    workspaceId: workspace.outputs.id
    tags: tags
    managedIdentityType: managedIdentityType
    managedIdentityName: managedIdentityName
    settings: [
      {
        name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
        value: 'false'
      }
      {
        name: 'AzureWebJobsStorage'
        value: storageAccount.outputs.connectionString
      }
      {
        name: 'FUNCTIONS_WORKER_RUNTIME'
        value: runtimeName
      }
      {
        name: 'FUNCTIONS_EXTENSION_VERSION'
        value: '~4'
      }
      {
        name: 'AZURE_CLIENT_ID'
        value: managedIdentityType == 'UserAssigned' ? managedIdentity.outputs.clientId : ''
      }
      {
        name: 'SERVICE_BUS_CONNECTION_STRING__fullyQualifiedNamespace'
        value: '${serviceBus.outputs.name}.servicebus.windows.net'
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        value: applicationInsights.outputs.connectionString
      }
      {
        name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING'
        value: managedIdentityType == 'UserAssigned' ? 'ClientId=${managedIdentity.outputs.clientId};Authorization=AAD' : ''
      }
      {
        name: 'INPUT_QUEUE_NAME'
        value: 'input'
      }
      {
        name: 'OUTPUT_QUEUE_NAME'
        value: 'output'
      }
      {
        name: 'NAMES'
        value: names
      }
      {
        name: 'TIMER_SCHEDULE'
        value: '*/10 * * * * *'
      }
    ]
  }
}

//********************************************
// Outputs
//********************************************
output functionAppName string = functionApp.outputs.name
output serviceBusName string = serviceBus.outputs.name
