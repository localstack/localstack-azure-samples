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
  'Premium'
  'PremiumV2'
  'Premium0V3'
  'PremiumV3'
  'PremiumMV3'
])
param skuTier string = 'Standard'

@description('Specifies the SKU name for the hosting plan.')
param skuName string = 'S1'

@description('Specifies the kind of the hosting plan.')
@allowed(['app','linux'])
param appServicePlanKind string = 'linux'

@description('Specifies whether the hosting plan is reserved.')
param reserved bool = true

@description('Specifies whether the hosting plan is zone redundant.')
param zoneRedundant bool = false

@description('Specifies the language runtime used by the Azure Web App.')
@allowed(['dotnet','python','java','node'])
param runtimeName string

@description('Specifies the target language version used by the Azure Web App.')
param runtimeVersion string

@description('Specifies the kind of the web app resource.')
param webAppKind string = 'app,linux'

@description('Specifies whether HTTPS is enforced for the Azure Web App.')
param httpsOnly bool = false

@description('Specifies the minimum TLS version for the Azure Web App.')
@allowed(['1.2','1.3'])
param minTlsVersion string = '1.2'

@description('Specifies whether the public network access is enabled or disabled')
@allowed(['Enabled','Disabled'])
param publicNetworkAccess string = 'Enabled'

@description('Specifies the optional Git Repo URL.')
param repoUrl string = ' '

@description('Specifies the username for the application (used to scope activities).')
param username string = 'paolo'

//
// MySQL flexible server
//
@description('Administrator login for the MySQL flexible server. Only used by the post-deploy mysql bootstrap; the Web App never authenticates with this account.')
param mysqlAdminLogin string = 'myadmin'

@description('Administrator login password for the MySQL flexible server.')
@secure()
param mysqlAdminPassword string

@description('MySQL major version.')
@allowed(['5.7','8.0.21'])
param mysqlVersion string = '8.0.21'

@description('Compute tier for the MySQL flexible server.')
@allowed(['Burstable','GeneralPurpose','MemoryOptimized'])
param mysqlSkuTier string = 'Burstable'

@description('Compute SKU name for the MySQL flexible server.')
param mysqlSkuName string = 'Standard_B1ms'

@description('Storage size in GB for the MySQL flexible server.')
@minValue(20)
@maxValue(16384)
param mysqlStorageSizeGB int = 32

@description('Backup retention in days for the MySQL flexible server.')
@minValue(1)
@maxValue(35)
param mysqlBackupRetentionDays int = 7

@description('Name of the application database to create on the MySQL flexible server.')
param databaseName string = 'PlannerDB'

//
// Networking
//
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

@description('Specifies the name of the subnet that hosts the private endpoint to the MySQL flexible server.')
param peSubnetName string = 'pe-subnet'

@description('Specifies the address prefix of the private-endpoint subnet.')
param peSubnetAddressPrefix string = '10.0.1.0/24'

@description('Specifies the name of the NSG associated to the private-endpoint subnet.')
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

@description('Specifies the name of the private endpoint targeting the MySQL flexible server.')
param mysqlPrivateEndpointName string = ''

//
// Observability
//
@description('Specifies the name of the Azure Log Analytics resource.')
param logAnalyticsName string = ''

@description('Specifies the service tier of the workspace.')
@allowed(['Free','Standalone','PerNode','PerGB2018'])
param logAnalyticsSku string = 'PerNode'

@description('Specifies the workspace data retention in days.')
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
var mysqlServerName = '${prefix}-mysqlflex-${suffix}'
var privateDnsZoneName = 'privatelink.mysql.database.azure.com'

// The MySQL flexible-server emulator embeds the LS-side TCP-proxy port directly in
// fullyQualifiedDomainName (e.g. "<srv>.mysql.database.localhost.localstack.cloud:4515").
// Real Azure returns just the bare host on 3306. Split on `:` so the Web App always gets the
// right host + port without any post-deploy shell logic.
var mysqlFqdnParts = split(mysqlServer.outputs.fqdn, ':')
var mysqlHost = mysqlFqdnParts[0]
var mysqlPort = length(mysqlFqdnParts) > 1 ? mysqlFqdnParts[1] : '3306'

//********************************************
// Modules and Resources
//********************************************
module workspace 'modules/log-analytics.bicep' = {
  name: 'workspace'
  params: {
    name: empty(logAnalyticsName) ? toLower('${prefix}-log-analytics-${suffix}') : logAnalyticsName
    location: location
    tags: tags
    sku: logAnalyticsSku
    retentionInDays: logAnalyticsRetentionInDays
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
    delegationServiceName: 'Microsoft.Web/serverfarms'
    workspaceId: workspace.outputs.id
    location: location
    tags: tags
  }
}

module mysqlServer 'modules/mysql-flexible-server.bicep' = {
  name: 'mysqlServer'
  params: {
    name: mysqlServerName
    location: location
    administratorLogin: mysqlAdminLogin
    administratorLoginPassword: mysqlAdminPassword
    version: mysqlVersion
    skuTier: mysqlSkuTier
    skuName: mysqlSkuName
    storageSizeGB: mysqlStorageSizeGB
    backupRetentionDays: mysqlBackupRetentionDays
    databaseName: databaseName
    workspaceId: workspace.outputs.id
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

module privateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'privateEndpoint'
  params: {
    name: empty(mysqlPrivateEndpointName)
      ? toLower('${prefix}-mysql-pe-${suffix}')
      : mysqlPrivateEndpointName
    privateLinkServiceId: mysqlServer.outputs.id
    privateDnsZoneId: privateDnsZone.outputs.id
    vnetId: network.outputs.virtualNetworkId
    subnetId: network.outputs.peSubnetId
    groupIds: [
      'mysqlServer'
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
    mysqlHost: mysqlHost
    mysqlPort: mysqlPort
    mysqlDatabase: mysqlServer.outputs.databaseName
    username: username
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

//********************************************
// Outputs
//********************************************
output webAppName string = webApp.outputs.name
output webAppDefaultHostName string = webApp.outputs.defaultHostName
output mysqlServerName string = mysqlServer.outputs.name
output mysqlFqdn string = mysqlServer.outputs.fqdn
output databaseName string = mysqlServer.outputs.databaseName
