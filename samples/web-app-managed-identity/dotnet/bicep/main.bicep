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
  'dotnetcore'
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

@description('Specifies the name of the diagnostic settings of the web app and of the App Service plan.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories that the diagnostic settings of the web app send to the Log Analytics workspace.')
param logCategories array = [
  'AppServiceHTTPLogs'
  'AppServiceConsoleLogs'
  'AppServiceAppLogs'
  'AppServiceAuditLogs'
  'AppServiceIPSecAuditLogs'
  'AppServicePlatformLogs'
  'AppServiceAuthenticationLogs'
]

@description('Specifies the metric categories that the diagnostic settings of the web app and of the App Service plan send to the Log Analytics workspace.')
param metricCategories array = [
  'AllMetrics'
]

//********************************************
// Variables
//********************************************
var webAppName = '${prefix}-webapp-${suffix}'
var appServicePlanName = '${prefix}-app-service-plan-${suffix}'
var storageAccountName = '${prefix}storage${suffix}'
var managedIdentityName = '${prefix}-identity-${suffix}'
var logAnalyticsName = '${prefix}-log-analytics-${suffix}'
var applicationInsightsName = '${prefix}-insights-${suffix}'

// The id of the Storage Blob Data Contributor built-in role
var storageBlobDataContributorRoleDefinitionId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

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

module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccount'
  params: {
    name: storageAccountName
    location: location
    skuName: storageAccountSku
    containerNames: [
      containerName
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
    zoneRedundant: appServicePlanZoneRedundant
    maximumElasticWorkerCount: skuTier == 'FlexConsumption' ? 1 : 20
    diagnosticSettingsName: diagnosticSettingsName
    metricCategories: metricCategories
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

module webApp 'modules/web-app.bicep' = {
  name: 'webApp'
  params: {
    name: webAppName
    location: location
    kind: webAppKind
    runtimeName: runtimeName
    runtimeVersion: runtimeVersion
    httpsOnly: httpsOnly
    minTlsVersion: minTlsVersion
    publicNetworkAccess: publicNetworkAccess
    identityType: managedIdentityType
    managedIdentityId: managedIdentityType == 'UserAssigned' ? managedIdentity!.outputs.id : ''
    hostingPlanName: appServicePlan.outputs.name
    appSettings: {
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
      ENABLE_ORYX_BUILD: 'true'
      CONTAINER_NAME: containerName
      AZURE_STORAGE_ACCOUNT_URL: storageAccount.outputs.blobEndpoint
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

// The web app's identity reads and writes the activities in the storage account: the system-assigned identity
// exists only once the web app does, so the role is assigned after the web app is created.
module storageBlobDataContributorRoleAssignment 'modules/storage-account-role-assignment.bicep' = {
  name: 'storageBlobDataContributorRoleAssignment'
  params: {
    storageAccountName: storageAccount.outputs.name
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
    principalId: managedIdentityType == 'SystemAssigned' ? webApp.outputs.principalId : managedIdentity!.outputs.principalId
  }
}

//********************************************
// Outputs
//********************************************
output appServicePlanName string = appServicePlan.outputs.name
output webAppName string = webApp.outputs.name
output webAppUrl string = webApp.outputs.defaultHostName
output storageAccountName string = storageAccount.outputs.name
output logAnalyticsName string = workspace.outputs.name
output applicationInsightsName string = applicationInsights.outputs.name
