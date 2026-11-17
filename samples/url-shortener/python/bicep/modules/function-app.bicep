//********************************************
// Parameters
//********************************************

@description('Specifies a globally unique name the Azure Function App.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the kind of the Azure Function App.')
@allowed([
  'functionapp'                            // Function Code App
  'functionapp,linux'                      // Linux Function App
  'functionapp,linux,container,kubernetes' // Function Container App on ARC
  'functionapp,linux,kubernetes'           // Function Code App on ARC
])
param kind string = 'functionapp,linux'

@description('Specifies the language runtime used by the Azure Function App.')
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

@description('Specifies the target language version used by the Azure Function App.')
param runtimeVersion string

@description('Specifies the minimum TLS version for the Azure Function App.')
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

@description('Specifies whether HTTPS is enforced for the Azure Function App.')
param httpsOnly bool = false

@description('Specifies whether the Azure Function App is always on. The functions with triggers other than HTTP need it on a dedicated App Service plan.')
param alwaysOn bool = true

@description('Specifies the type of managed identity of the Azure Function App.')
@allowed([
  'SystemAssigned'
  'UserAssigned'
])
param identityType string = 'SystemAssigned'

@description('Specifies the resource id of the user-assigned managed identity of the Azure Function App. Used only when identityType is UserAssigned.')
param managedIdentityId string = ''

@description('Specifies the name of the hosting plan.')
param hostingPlanName string

@description('Specifies the name of the storage account that the Functions host uses for its own data (AzureWebJobsStorage).')
param storageAccountName string

@description('Specifies the app settings of the Azure Function App, besides AzureWebJobsStorage, FUNCTIONS_EXTENSION_VERSION and FUNCTIONS_WORKER_RUNTIME, which the module sets.')
param appSettings object = {}

@description('Specifies the blob, queue and table endpoints of the storage account (blob, queue, table). When given, the connection strings the module builds name them instead of an EndpointSuffix, which the Functions host\'s storage clients cannot parse when it carries the emulator\'s port.')
param storageEndpoints object = {}

@description('Specifies the name of an app setting that the module sets to the connection string of the storage account, for the bindings of the functions that connect with a key. Empty for none.')
param storageConnectionStringSettingName string = ''

@description('Specifies the optional Git Repo URL.')
param repoUrl string = ''

@description('Specifies the branch of the optional Git repository.')
param repoBranch string = 'master'

@description('Specifies whether the optional Git repository is integrated manually.')
param isManualIntegration bool = true

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories that the diagnostic settings of the Azure Function App send to the Log Analytics workspace.')
param logCategories array = [
  'FunctionAppLogs'
]

@description('Specifies the metric categories that the diagnostic settings of the Azure Function App send to the Log Analytics workspace.')
param metricCategories array = [
  'AllMetrics'
]

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************

var logs = [
  for category in logCategories: {
    category: category
    enabled: true
  }
]
var metrics = [
  for category in metricCategories: {
    category: category
    enabled: true
  }
]
// The key is read when this module deploys, once the storage account exists, and stays out of the deployment history
var storageAccountKey = storageAccount.listKeys().keys[0].value
var storageConnectionString = empty(storageEndpoints) ? 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccountKey}' : 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccountKey};BlobEndpoint=${storageEndpoints.blob};QueueEndpoint=${storageEndpoints.queue};TableEndpoint=${storageEndpoints.table}'

//********************************************
// Resources
//********************************************

resource hostingPlan 'Microsoft.Web/serverfarms@2024-11-01' existing = {
  name: hostingPlanName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' existing = {
  name: storageAccountName
}

resource functionApp 'Microsoft.Web/sites@2024-11-01' = {
  name: name
  location: location
  tags: tags
  kind: kind
  properties: {
    httpsOnly: httpsOnly
    reserved: true
    serverFarmId: hostingPlan.id
    siteConfig: {
      alwaysOn: alwaysOn
      linuxFxVersion: toUpper('${runtimeName}|${runtimeVersion}')
      minTlsVersion: minTlsVersion
      ftpsState: 'FtpsOnly'
      publicNetworkAccess: publicNetworkAccess
    }
  }
  identity: {
    type: identityType
    userAssignedIdentities: identityType == 'UserAssigned' ? {
      '${managedIdentityId}': {}
    } : null
  }
}

resource configAppSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: functionApp
  name: 'appsettings'
  // The app settings passed in win over the defaults
  properties: union({
    AzureWebJobsStorage: storageConnectionString
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: runtimeName
  }, empty(storageConnectionStringSettingName) ? {} : {
    '${storageConnectionStringSettingName}': storageConnectionString
  }, appSettings)
}

resource functionAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2024-11-01' = if (contains(repoUrl, 'http')) {
  name: 'web'
  parent: functionApp
  properties: {
    repoUrl: repoUrl
    branch: repoBranch
    isManualIntegration: isManualIntegration
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: functionApp
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************
output id string = functionApp.id
output name string = functionApp.name
output defaultHostName string = functionApp.properties.defaultHostName
// The principal id of the system-assigned identity, the value its role assignments are keyed on; empty for a
// user-assigned identity, whose principal id comes from the managed identity module.
output principalId string = identityType == 'SystemAssigned' ? functionApp.identity.principalId : ''
