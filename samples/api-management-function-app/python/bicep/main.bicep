//********************************************
// Parameters
//********************************************

@description('Prefix applied to every resource name in this sample.')
param prefix string = 'local'

@description('Suffix applied to every resource name in this sample.')
param suffix string = 'test'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Language runtime of the Function App.')
param runtimeName string = 'python'

@description('Runtime version of the Function App.')
param runtimeVersion string = '3.11'

@description('SKU of the Linux App Service plan hosting the Function App.')
param appServicePlanSku string = 'B1'

@description('SKU of the API Management service. Consumption provisions in minutes; the classic tiers take much longer.')
param apimSkuName string = 'Consumption'

@description('Name of the organisation publishing the APIs.')
param publisherName string = 'LocalStack'

@description('E-mail address API Management sends its notifications to.')
param publisherEmail string = 'noreply@localstack.cloud'

@description('Scheme API Management uses to call the Function App. The emulator serves it over plain HTTP; use https on real Azure.')
@allowed([
  'http'
  'https'
])
param backendScheme string = 'http'

@description('Shared secret the gateway adds to every backend call; generated per run by deploy.sh.')
@secure()
param backendSecret string

@description('SKU tier of the Linux App Service plan hosting the Function App.')
param appServicePlanTier string = 'Basic'

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

//
// Observability
//
@description('Specifies the name of the Azure Log Analytics resource.')
param logAnalyticsName string = ''

@description('Specifies the name of the Azure Application Insights resource.')
param applicationInsightsName string = ''

@description('Specifies the service tier of the workspace.')
@allowed(['Free','Standalone','PerNode','PerGB2018'])
param logAnalyticsSku string = 'PerNode'

@description('Specifies the workspace data retention in days.')
param logAnalyticsRetentionInDays int = 60

//********************************************
// Variables
//********************************************

var storageAccountName = '${prefix}invstorage${suffix}'
var appServicePlanName = '${prefix}-inventory-app-service-plan-${suffix}'
var functionAppName = '${prefix}-inventory-functionapp-${suffix}'
var apimName = '${prefix}-inventory-apim-${suffix}'

//********************************************
// Monitoring: the workspace and Application Insights
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

module applicationInsights 'modules/application-insights.bicep' = {
  name: 'applicationInsights'
  params: {
    name: empty(applicationInsightsName) ? toLower('${prefix}-insights-${suffix}') : applicationInsightsName
    location: location
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

//********************************************
// Function App: the Inventory backend
//********************************************

// The storage account of the Functions host, whose blob, queue and table services send their logs to the workspace
module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccount'
  params: {
    name: storageAccountName
    location: location
    diagnosticServices: [
      'blob'
      'queue'
      'table'
    ]
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'appServicePlan'
  params: {
    name: appServicePlanName
    location: location
    skuTier: appServicePlanTier
    skuName: appServicePlanSku
    kind: 'linux'
    reserved: true
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

module functionApp 'modules/function-app.bicep' = {
  name: 'functionApp'
  params: {
    name: functionAppName
    location: location
    kind: 'functionapp,linux'
    runtimeName: runtimeName
    runtimeVersion: runtimeVersion
    // Plain HTTP while the gateway calls this app over http://: the emulator serves the Function App that way; with
    // backendScheme = https the app accepts only HTTPS, as on real Azure.
    httpsOnly: backendScheme == 'https'
    // On a Dedicated (App Service) plan the Functions host goes idle without this, and a gateway call then waits for a
    // cold start.
    alwaysOn: true
    hostingPlanName: appServicePlan.outputs.name
    storageAccountName: storageAccount.outputs.name
    appSettings: {
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
      ENABLE_ORYX_BUILD: 'true'
      // The same secret the gateway injects from its named value
      BACKEND_SECRET: backendSecret
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.outputs.connectionString
      // The Python worker sends its own telemetry through OpenTelemetry, which host.json turns on, instead of the host
      // forwarding its log records, and only the records of the function's logger
      PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY: 'true'
      PYTHON_APPLICATIONINSIGHTS_LOGGER_NAME: 'function_app'
    }
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

//********************************************
// API Management
//********************************************

module apiManagement 'modules/api-management.bicep' = {
  name: 'apiManagement'
  params: {
    name: apimName
    location: location
    skuName: apimSkuName
    publisherName: publisherName
    publisherEmail: publisherEmail
    backendSecret: backendSecret
    // The backend is the Function App: the emulator answers on plain HTTP under its own hostname (use https:// on real
    // Azure)
    serviceUrl: '${backendScheme}://${functionApp.outputs.defaultHostName}/api'
    openApiDocument: loadTextContent('../apim/openapi.json')
    apiPolicy: loadTextContent('../apim/inventory-api-policy.xml')
    workspaceId: workspace.outputs.id
    tags: tags
  }
}

//********************************************
// Outputs
//********************************************

output resourceGroupName string = resourceGroup().name
output functionAppName string = functionApp.outputs.name
output functionAppHostName string = functionApp.outputs.defaultHostName
output apimName string = apiManagement.outputs.name
output gatewayUrl string = apiManagement.outputs.gatewayUrl
output apiPath string = apiManagement.outputs.apiPath
output subscriptionName string = apiManagement.outputs.subscriptionName
output logAnalyticsName string = workspace.outputs.name
output applicationInsightsName string = applicationInsights.outputs.name
