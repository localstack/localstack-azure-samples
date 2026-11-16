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
param skuTier string = 'Basic'

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
param skuName string = 'B1'

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

@description('Specifies the kind of the Azure Function App.')
@allowed([
  'functionapp'                            // Function Code App
  'functionapp,linux'                      // Linux Function App
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

@description('Specifies whether Always On is enabled for the Azure Functions App: on an App Service plan, the Functions runtime goes idle after a few minutes of inactivity, and only HTTP requests wake it up.')
param alwaysOn bool = true

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
param inputTableName string = 'scoreboards'

@description('Specifies the name of the output table.')
param outputTableName string = 'winners'

@description('Specifies the comma-separated list of player names.')
param playerNames string = 'Alice,Anastasia,Paolo,Leo,Mia'

@description('Specifies the timer schedule for the timer triggered function.')
param timerSchedule string = '0 */1 * * * *'

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

@description('Specifies the name of the diagnostic settings of the function app and of the App Service plan.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories that the diagnostic settings of the function app send to the Log Analytics workspace.')
param logCategories array = [
  'FunctionAppLogs'
]

@description('Specifies the metric categories that the diagnostic settings of the function app and of the App Service plan send to the Log Analytics workspace.')
param metricCategories array = [
  'AllMetrics'
]

//********************************************
// Variables
//********************************************
var functionAppName = '${prefix}-functionapp-${suffix}'
var appServicePlanName = '${prefix}-app-service-plan-${suffix}'
var storageAccountName = '${prefix}storage${suffix}'
var logAnalyticsName = '${prefix}-log-analytics-${suffix}'
var applicationInsightsName = '${prefix}-insights-${suffix}'

//********************************************
// Modules
//********************************************
module workspace 'modules/log-analytics.bicep' = {
  name: 'workspace'
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
  }
}

module applicationInsights 'modules/application-insights.bicep' = {
  name: 'applicationInsights'
  params: {
    name: applicationInsightsName
    location: location
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

// The functions use the blobs, the queues and the tables of the storage account, where the Functions host also keeps
// its own data (AzureWebJobsStorage), so the three services have diagnostic settings. The functions create their
// containers, queues and tables themselves when they start.
module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccount'
  params: {
    name: storageAccountName
    location: location
    skuName: storageAccountSku
    diagnosticServices: [
      'blob'
      'queue'
      'table'
    ]
    diagnosticSettingsName: diagnosticSettingsName
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'appServicePlan'
  params: {
    name: appServicePlanName
    location: location
    skuTier: skuTier
    skuName: skuName
    kind: appServicePlanKind
    reserved: reserved
    zoneRedundant: zoneRedundant
    maximumElasticWorkerCount: skuTier == 'FlexConsumption' ? 1 : 20
    diagnosticSettingsName: diagnosticSettingsName
    metricCategories: metricCategories
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

module functionApp 'modules/function-app.bicep' = {
  name: 'functionApp'
  params: {
    name: functionAppName
    location: location
    kind: functionAppKind
    runtimeName: runtimeName
    runtimeVersion: runtimeVersion
    httpsOnly: httpsOnly
    alwaysOn: alwaysOn
    minTlsVersion: minTlsVersion
    publicNetworkAccess: publicNetworkAccess
    hostingPlanName: appServicePlan.outputs.name
    storageAccountName: storageAccount.outputs.name
    // The bindings of the functions connect to the storage account with the connection string of this setting
    storageConnectionStringSettingName: 'STORAGE_ACCOUNT_CONNECTION_STRING'
    appSettings: {
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
      INPUT_STORAGE_CONTAINER_NAME: inputContainerName
      OUTPUT_STORAGE_CONTAINER_NAME: outputContainerName
      INPUT_QUEUE_NAME: inputQueueName
      OUTPUT_QUEUE_NAME: outputQueueName
      TRIGGER_QUEUE_NAME: triggerQueueName
      INPUT_TABLE_NAME: inputTableName
      OUTPUT_TABLE_NAME: outputTableName
      PLAYER_NAMES: playerNames
      TIMER_SCHEDULE: timerSchedule
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.outputs.connectionString
    }
    repoUrl: repoUrl
    repoBranch: 'main'
    diagnosticSettingsName: diagnosticSettingsName
    logCategories: logCategories
    metricCategories: metricCategories
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

//********************************************
// Outputs
//********************************************
output functionAppName string = functionApp.outputs.name
output storageAccountName string = storageAccount.outputs.name
output logAnalyticsName string = workspace.outputs.name
output applicationInsightsName string = applicationInsights.outputs.name
