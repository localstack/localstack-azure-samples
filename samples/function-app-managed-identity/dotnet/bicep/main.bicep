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

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

@description('Specifies the sku of the Azure Storage account.')
param storageAccountSku string = 'Standard_LRS'

@description('Specifies the name of the input container.')
param inputContainerName string = 'input'

@description('Specifies the name of the output container.')
param outputContainerName string = 'output'

@description('Specifies the type of managed identity.')
@allowed([
  'SystemAssigned'
  'UserAssigned'
])
param managedIdentityType string = 'SystemAssigned'

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
var managedIdentityName = '${prefix}-identity-${suffix}'
var logAnalyticsName = '${prefix}-log-analytics-${suffix}'
var applicationInsightsName = '${prefix}-insights-${suffix}'

// The ids of the Storage Blob Data Contributor and Storage Queue Data Contributor built-in roles
var storageBlobDataContributorRoleDefinitionId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var storageQueueDataContributorRoleDefinitionId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'

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

// The Functions host keeps its own data in the blobs, queues and tables of the storage account (AzureWebJobsStorage),
// so the three services have diagnostic settings
module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccount'
  params: {
    name: storageAccountName
    location: location
    skuName: storageAccountSku
    containerNames: [
      inputContainerName
      outputContainerName
    ]
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

module managedIdentity 'modules/managed-identity.bicep' = if (managedIdentityType == 'UserAssigned') {
  name: 'managedIdentity'
  params: {
    name: managedIdentityName
    location: location
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
    identityType: managedIdentityType
    managedIdentityId: managedIdentityType == 'UserAssigned' ? managedIdentity!.outputs.id : ''
    hostingPlanName: appServicePlan.outputs.name
    storageAccountName: storageAccount.outputs.name
    appSettings: {
      // The deployment uploads the published output: no build on the server
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
      STORAGE_ACCOUNT_CONNECTION_STRING__blobServiceUri: storageAccount.outputs.blobEndpoint
      STORAGE_ACCOUNT_CONNECTION_STRING__queueServiceUri: storageAccount.outputs.queueEndpoint
      STORAGE_ACCOUNT_CONNECTION_STRING__tableServiceUri: storageAccount.outputs.tableEndpoint
      INPUT_STORAGE_CONTAINER_NAME: inputContainerName
      OUTPUT_STORAGE_CONTAINER_NAME: outputContainerName
      AZURE_CLIENT_ID: managedIdentityType == 'UserAssigned' ? managedIdentity!.outputs.clientId : ''
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.outputs.connectionString
    }
    repoUrl: repoUrl
    diagnosticSettingsName: diagnosticSettingsName
    logCategories: logCategories
    metricCategories: metricCategories
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

// The function app's identity reads the input blobs, writes the output blobs and reads the queue of the blob trigger:
// the system-assigned identity exists only once the function app does, so the roles are assigned after it's created.
module storageBlobDataContributorRoleAssignment 'modules/storage-account-role-assignment.bicep' = {
  name: 'storageBlobDataContributorRoleAssignment'
  params: {
    storageAccountName: storageAccount.outputs.name
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
    principalId: managedIdentityType == 'SystemAssigned' ? functionApp.outputs.principalId : managedIdentity!.outputs.principalId
  }
}

module storageQueueDataContributorRoleAssignment 'modules/storage-account-role-assignment.bicep' = {
  name: 'storageQueueDataContributorRoleAssignment'
  params: {
    storageAccountName: storageAccount.outputs.name
    roleDefinitionId: storageQueueDataContributorRoleDefinitionId
    principalId: managedIdentityType == 'SystemAssigned' ? functionApp.outputs.principalId : managedIdentity!.outputs.principalId
  }
}

//********************************************
// Outputs
//********************************************
output appServicePlanName string = appServicePlan.outputs.name
output functionAppName string = functionApp.outputs.name
output functionAppUrl string = functionApp.outputs.defaultHostName
output storageAccountName string = storageAccount.outputs.name
output logAnalyticsName string = workspace.outputs.name
output applicationInsightsName string = applicationInsights.outputs.name
