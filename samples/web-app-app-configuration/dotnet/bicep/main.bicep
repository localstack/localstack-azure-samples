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
@allowed(['dotnet','dotnetcore','python','java','node'])
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
// PostgreSQL flexible server
//
@description('Administrator login for the PostgreSQL flexible server. Only used by the post-deploy psql bootstrap; the Web App never authenticates with this account.')
param pgAdminLogin string = 'pgadmin'

@description('Administrator login password for the PostgreSQL flexible server.')
@secure()
param pgAdminPassword string

@description('PostgreSQL major version.')
@allowed(['13','14','15','16','17'])
param pgVersion string = '16'

@description('Compute tier for the PostgreSQL flexible server.')
@allowed(['Burstable','GeneralPurpose','MemoryOptimized'])
param pgSkuTier string = 'Burstable'

@description('Compute SKU name for the PostgreSQL flexible server.')
param pgSkuName string = 'Standard_B1ms'

@description('Storage size in GB for the PostgreSQL flexible server.')
@minValue(32)
@maxValue(16384)
param pgStorageSizeGB int = 32

@description('Backup retention in days for the PostgreSQL flexible server.')
@minValue(7)
@maxValue(35)
param pgBackupRetentionDays int = 7

@description('Name of the application database to create on the PostgreSQL flexible server.')
param databaseName string = 'PlannerDB'

@description('Name of the PostgreSQL application role the Web App connects with. Stored in Key Vault as the pg-user secret; the role itself is created by the post-deploy psql bootstrap.')
param pgAppUser string = 'testuser'

@description('Password of the PostgreSQL application role. Stored in Key Vault as the pg-password secret.')
@secure()
param pgAppPassword string

//
// App Configuration and Key Vault
//
@description('Specifies the name of the App Configuration store (globally unique).')
param appConfigurationName string = ''

@description('Specifies the SKU of the App Configuration store.')
@allowed(['Developer','Standard','Premium'])
param appConfigurationSku string = 'Standard'

@description('Specifies the name of the key vault (globally unique).')
param keyVaultName string = ''

@description('Specifies the SKU of the key vault.')
@allowed(['standard','premium'])
param keyVaultSkuName string = 'standard'

@description('Specifies the name of the user-assigned managed identity of the Web App.')
param managedIdentityName string = ''

@description('Specifies the object id of the deploying principal, granted Key Vault Secrets Officer on the vault (empty skips the assignment).')
param deployerPrincipalId string = ''

@description('Specifies the principal type of the deploying principal.')
@allowed(['User','ServicePrincipal','Group'])
param deployerPrincipalType string = 'User'

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

@description('Specifies the name of the subnet that hosts the private endpoints to PostgreSQL, App Configuration and Key Vault.')
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

@description('Specifies the name of the private endpoint targeting the PostgreSQL flexible server.')
param postgresPrivateEndpointName string = ''

@description('Specifies the name of the private endpoint targeting the App Configuration store.')
param appConfigurationPrivateEndpointName string = ''

@description('Specifies the name of the private endpoint targeting the key vault.')
param keyVaultPrivateEndpointName string = ''

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
var pgServerName = '${prefix}-pgflex-${suffix}'
var postgresPrivateDnsZoneName = 'privatelink.postgres.database.azure.com'
var appConfigurationPrivateDnsZoneName = 'privatelink.azconfig.io'
var keyVaultPrivateDnsZoneName = 'privatelink.vaultcore.azure.net'
var keyVaultReferenceContentType = 'application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8'

// The PostgreSQL flexible-server emulator embeds the LS-side TCP-proxy port directly in
// fullyQualifiedDomainName (e.g. "<srv>.postgres.database.localhost.localstack.cloud:4515").
// Real Azure returns just the bare host on 5432. Split on `:` so the store always gets the
// right host + port without any post-deploy shell logic.
var pgFqdnParts = split(postgresqlServer.outputs.fqdn, ':')
var pgHost = pgFqdnParts[0]
var pgPort = length(pgFqdnParts) > 1 ? pgFqdnParts[1] : '5432'

// The five settings the web app used to receive as app settings, seeded into the App Configuration store:
// three plain key-values and two Key Vault references to the secrets created by the key-vault module.
// A Key Vault reference value is the JSON document {"uri":"<secret identifier>"}. It is written with string
// interpolation rather than string({ uri: ... }): the result is identical on Azure, while the LocalStack
// emulator's template engine renders string() of an object as a Python dictionary instead of JSON today.
var appConfigurationKeyValues = [
  {
    key: 'PG_HOST'
    value: pgHost
    contentType: ''
  }
  {
    key: 'PG_PORT'
    value: pgPort
    contentType: ''
  }
  {
    key: 'PG_DATABASE'
    value: postgresqlServer.outputs.databaseName
    contentType: ''
  }
  {
    key: 'PG_USER'
    value: '{"uri":"${keyVault.outputs.secretUris.pgUser}"}'
    contentType: keyVaultReferenceContentType
  }
  {
    key: 'PG_PASSWORD'
    value: '{"uri":"${keyVault.outputs.secretUris.pgPassword}"}'
    contentType: keyVaultReferenceContentType
  }
]

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

module managedIdentity 'modules/managed-identity.bicep' = {
  name: 'managedIdentity'
  params: {
    name: empty(managedIdentityName) ? toLower('${prefix}-identity-${suffix}') : managedIdentityName
    location: location
    tags: tags
  }
}

module postgresqlServer 'modules/postgresql-flexible-server.bicep' = {
  name: 'postgresqlServer'
  params: {
    name: pgServerName
    location: location
    administratorLogin: pgAdminLogin
    administratorLoginPassword: pgAdminPassword
    version: pgVersion
    skuTier: pgSkuTier
    skuName: pgSkuName
    storageSizeGB: pgStorageSizeGB
    backupRetentionDays: pgBackupRetentionDays
    databaseName: databaseName
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'keyVault'
  params: {
    name: empty(keyVaultName) ? toLower('${prefix}-keyvault-${suffix}') : keyVaultName
    location: location
    skuName: keyVaultSkuName
    pgAppUser: pgAppUser
    pgAppPassword: pgAppPassword
    identityPrincipalId: managedIdentity.outputs.principalId
    deployerPrincipalId: deployerPrincipalId
    deployerPrincipalType: deployerPrincipalType
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

module appConfiguration 'modules/app-configuration.bicep' = {
  name: 'appConfiguration'
  params: {
    name: empty(appConfigurationName) ? toLower('${prefix}-appconfig-${suffix}') : appConfigurationName
    location: location
    skuName: appConfigurationSku
    keyValues: appConfigurationKeyValues
    dataReaderPrincipalId: managedIdentity.outputs.principalId
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

module postgresPrivateDnsZone 'modules/private-dns-zone.bicep' = {
  name: 'postgresPrivateDnsZone'
  params: {
    name: postgresPrivateDnsZoneName
    vnetId: network.outputs.virtualNetworkId
    tags: tags
  }
}

module postgresPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'postgresPrivateEndpoint'
  params: {
    name: empty(postgresPrivateEndpointName)
      ? toLower('${prefix}-postgres-pe-${suffix}')
      : postgresPrivateEndpointName
    privateLinkServiceId: postgresqlServer.outputs.id
    privateDnsZoneId: postgresPrivateDnsZone.outputs.id
    subnetId: network.outputs.peSubnetId
    groupIds: [
      'postgresqlServer'
    ]
    location: location
    tags: tags
  }
}

module appConfigurationPrivateDnsZone 'modules/private-dns-zone.bicep' = {
  name: 'appConfigurationPrivateDnsZone'
  params: {
    name: appConfigurationPrivateDnsZoneName
    vnetId: network.outputs.virtualNetworkId
    tags: tags
  }
}

module appConfigurationPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'appConfigurationPrivateEndpoint'
  params: {
    name: empty(appConfigurationPrivateEndpointName)
      ? toLower('${prefix}-appconfig-pe-${suffix}')
      : appConfigurationPrivateEndpointName
    privateLinkServiceId: appConfiguration.outputs.id
    privateDnsZoneId: appConfigurationPrivateDnsZone.outputs.id
    subnetId: network.outputs.peSubnetId
    groupIds: [
      'configurationStores'
    ]
    location: location
    tags: tags
  }
}

module keyVaultPrivateDnsZone 'modules/private-dns-zone.bicep' = {
  name: 'keyVaultPrivateDnsZone'
  params: {
    name: keyVaultPrivateDnsZoneName
    vnetId: network.outputs.virtualNetworkId
    tags: tags
  }
}

module keyVaultPrivateEndpoint 'modules/private-endpoint.bicep' = {
  name: 'keyVaultPrivateEndpoint'
  params: {
    name: empty(keyVaultPrivateEndpointName)
      ? toLower('${prefix}-keyvault-pe-${suffix}')
      : keyVaultPrivateEndpointName
    privateLinkServiceId: keyVault.outputs.id
    privateDnsZoneId: keyVaultPrivateDnsZone.outputs.id
    subnetId: network.outputs.peSubnetId
    groupIds: [
      'vault'
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

// The web app is created after the store (with its key-values and role assignment) and the vault (with its
// secrets and role assignment): the endpoint and client id it receives come from the store and identity
// modules, and the store module itself depends on the vault module through the secret URIs.
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
    managedIdentityId: managedIdentity.outputs.id
    managedIdentityClientId: managedIdentity.outputs.clientId
    appConfigurationEndpoint: appConfiguration.outputs.endpoint
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
output postgresServerName string = postgresqlServer.outputs.name
output postgresFqdn string = postgresqlServer.outputs.fqdn
output databaseName string = postgresqlServer.outputs.databaseName
output appConfigurationName string = appConfiguration.outputs.name
output appConfigurationEndpoint string = appConfiguration.outputs.endpoint
output keyVaultName string = keyVault.outputs.name
output keyVaultUri string = keyVault.outputs.vaultUri
output managedIdentityName string = managedIdentity.outputs.name
output managedIdentityClientId string = managedIdentity.outputs.clientId
