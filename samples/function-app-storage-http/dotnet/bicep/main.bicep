@description('Specifies the prefix for the name of the Azure resources.')
@minLength(2)
param prefix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the suffix for the name of the Azure resources.')
@minLength(2)
param suffix string = take(uniqueString(resourceGroup().id), 4)

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Specifies the sku of the Azure Storage account.')
param storageAccountSku string = 'Standard_LRS'

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

@description('Optional Git Repo URL')
param repoUrl string = ' '

@description('Specifies the name of the input container.')
param inputContainerName string = 'input'

@description('Specifies the name of the output container.')
param outputContainerName string = 'output'

@description('Specifies the name of the input queue.')
param inputQueueName string = 'input'

@description('Specifies the name of the output queue.')
param outputQueueName string = 'output'

@description('Specifies the name of the trigger queue.')
param triggerQueueName string = 'trigger'

@description('Specifies the name of the input table.')
param inputTableName string = 'input'

@description('Specifies the name of the output table.')
param outputTableName string = 'output'

@description('Specifies the comma-separated list of player names.')
param playerNames string = 'Alice,Anastasia,Paolo,Leo,Mia'

@description('Specifies the timer schedule for the timer triggered function.')
param timerSchedule string = '0 */1 * * * *'

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

var functionAppName = '${prefix}-functionapp-${suffix}'
var appServicePlanPortalName = '${prefix}-app-service-plan-${suffix}'
var storageAccountName = '${prefix}storage${suffix}'
var storageAccountConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

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

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanPortalName
  location: location
  tags: tags
  kind: appServicePlanKind
  sku: {
    tier: skuTier
    name: skuName
  }
  properties: {
    reserved: reserved
    zoneRedundant: zoneRedundant
     maximumElasticWorkerCount: skuTier == 'FlexConsumption' ? 1 : 20
  }
}

resource functionApp 'Microsoft.Web/sites@2024-11-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: functionAppKind
  properties: {
    httpsOnly: httpsOnly
    reserved: true
    serverFarmId: appServicePlan.id
    virtualNetworkSubnetId: null
    siteConfig: {
      linuxFxVersion: toUpper('${runtimeName}|${runtimeVersion}')
      minTlsVersion: minTlsVersion
      ftpsState: 'FtpsOnly'
      publicNetworkAccess: publicNetworkAccess
    }
  }
  identity: {
    type: 'SystemAssigned'
  }

  resource configAppSettings 'config' = {
    name: 'appsettings'
    properties: {
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
      AzureWebJobsStorage: storageAccountConnectionString
	    WEBSITE_STORAGE_ACCOUNT_CONNECTION_STRING: storageAccountConnectionString
	    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: storageAccountConnectionString
      STORAGE_ACCOUNT_CONNECTION_STRING: storageAccountConnectionString
      INPUT_STORAGE_CONTAINER_NAME: inputContainerName
      OUTPUT_STORAGE_CONTAINER_NAME: outputContainerName
      INPUT_QUEUE_NAME: inputQueueName
      OUTPUT_QUEUE_NAME: outputQueueName
      TRIGGER_QUEUE_NAME: triggerQueueName
      INPUT_TABLE_NAME: inputTableName
      OUTPUT_TABLE_NAME: outputTableName
      PLAYER_NAMES: playerNames
      TIMER_SCHEDULE: timerSchedule
      FUNCTIONS_WORKER_RUNTIME: runtimeName
    }
  }
}

resource functionAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2024-11-01' = if (contains(repoUrl,'http')){
  name: 'web'
  parent: functionApp
  properties: {
    repoUrl: repoUrl
    branch: 'main'
    isManualIntegration: true
  }
}

output functionAppName string = functionAppName
output storageAccountName string = storageAccountName
output storageAccountConnectionString string = storageAccountConnectionString
