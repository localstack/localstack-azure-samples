//********************************************
// Parameters
//********************************************

@description('Specifies a globally unique name the Azure Web App.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the language runtime used by the Azure Web App.')
param runtimeName string

@description('Specifies the target language version used by the Azure Web App.')
param runtimeVersion string

@description('Specifies whether HTTPS is enforced for the Azure Web App.')
param httpsOnly bool = false

@description('Specifies the name of the hosting plan.')
param hostingPlanName string

@description('Specifies the resource id of the user-assigned managed identity the web app authenticates with.')
param managedIdentityId string

@description('Specifies the app settings of the web app, besides the Service Bus connection string, which the module sets.')
param appSettings object = {}

@description('Specifies the name of the Service Bus namespace whose RootManageSharedAccessKey connection string the web app receives. The module reads it when it deploys, once the namespace exists, and the key stays out of the deployment history.')
param serviceBusNamespaceName string

@description('Specifies the name of the app setting that receives the connection string of the Service Bus namespace.')
param serviceBusConnectionStringSettingName string = 'SB_CONN'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories enabled by the diagnostic settings.')
param logCategories array = [
  'AppServiceHTTPLogs'
  'AppServiceConsoleLogs'
  'AppServiceAppLogs'
  'AppServiceAuditLogs'
  'AppServiceIPSecAuditLogs'
  'AppServicePlatformLogs'
  'AppServiceAuthenticationLogs'
]

@description('Specifies the metric categories enabled by the diagnostic settings.')
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

//********************************************
// Resources
//********************************************

resource hostingPlan 'Microsoft.Web/serverfarms@2024-11-01' existing = {
  name: hostingPlanName
}

resource serviceBusRootAuthorizationRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2024-01-01' existing = {
  name: '${serviceBusNamespaceName}/RootManageSharedAccessKey'
}

resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: name
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    httpsOnly: httpsOnly
    reserved: true
    serverFarmId: hostingPlan.id
    siteConfig: {
      linuxFxVersion: toUpper('${runtimeName}|${runtimeVersion}')
    }
  }
  // The user-assigned managed identity that the storage, Key Vault and Service Bus modules give their data roles to:
  // AZURE_CLIENT_ID in the app settings tells DefaultAzureCredential in the app to use it.
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
}

resource configAppSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: webApp
  name: 'appsettings'
  properties: union(appSettings, {
    '${serviceBusConnectionStringSettingName}': serviceBusRootAuthorizationRule.listKeys().primaryConnectionString
  })
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: webApp
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************

output id string = webApp.id
output name string = webApp.name
output defaultHostName string = webApp.properties.defaultHostName
