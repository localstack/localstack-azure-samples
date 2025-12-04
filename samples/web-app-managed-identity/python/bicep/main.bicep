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
param appServicePlanZoneRedundant bool = false

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

@description('Specifies the optional Git Repo URL.')
param repoUrl string = ''

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

@description('Specifies the sku of the Azure Storage account.')
param storageAccountSku string = 'Standard_LRS'

@description('Specifies the name of the blob container.')
param containerName string = 'activities'

@description('Specifies the type of managed identity.')
@allowed([
  'SystemAssigned'
  'UserAssigned'
])
param managedIdentityType string = 'SystemAssigned'

var webAppName = '${prefix}-webapp-${suffix}'
var appServicePlanName = '${prefix}-app-service-plan-${suffix}'
var storageAccountName = '${prefix}storage${suffix}'
var managedIdentityName = '${prefix}-identity-${suffix}'

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (managedIdentityType == 'UserAssigned') {
  name: managedIdentityName
  location: location
  tags: tags
}

resource storageBlobDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  scope: subscription()
}

resource storageBlobDataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, webApp.id, storageBlobDataContributorRoleDefinition.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleDefinition.id
    principalId: managedIdentityType == 'SystemAssigned' ? webApp.identity.principalId : managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  parent: blobServices
  name: containerName
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  kind: appServicePlanKind
  sku: {
    tier: skuTier
    name: skuName
  }
  properties: {
    reserved: reserved
    zoneRedundant: appServicePlanZoneRedundant
     maximumElasticWorkerCount: skuTier == 'FlexConsumption' ? 1 : 20
  }
}

resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: webAppName
  location: location
  tags: tags
  kind: webAppKind
  properties: {
    httpsOnly: httpsOnly
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: toUpper('${runtimeName}|${runtimeVersion}')
      minTlsVersion: minTlsVersion
      publicNetworkAccess: publicNetworkAccess
    }
  }
  identity: {
    type: managedIdentityType
    userAssignedIdentities  : managedIdentityType == 'SystemAssigned' ? null : {
      '${managedIdentity.id}': {}
    } 
  }
}

resource configAppSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: webApp
  name: 'appsettings'
  properties: {
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    ENABLE_ORYX_BUILD: 'true'
    CONTAINER_NAME: container.name
    AZURE_STORAGE_ACCOUNT_URL: storageAccount.properties.primaryEndpoints.blob
    AZURE_CLIENT_ID: managedIdentityType == 'SystemAssigned' ? '' : managedIdentity.properties.clientId
  }
  dependsOn: [
    storageBlobDataOwnerRoleAssignment
  ]
}

resource webAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2024-11-01' = if (contains(repoUrl,'http')){
  name: 'web'
  parent: webApp
  properties: {
    repoUrl: repoUrl
    branch: 'master'
    isManualIntegration: true
  }
}

output appServicePlanName string = appServicePlan.name
output webAppName string = webApp.name
output webAppUrl string = webApp.properties.defaultHostName
output storageAccountName string = storageAccountName
