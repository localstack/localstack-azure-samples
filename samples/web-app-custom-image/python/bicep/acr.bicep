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

@description('Specifies the name of the Azure Log Analytics resource.')
param logAnalyticsName string = ''

@description('Specifies the service tier of the workspace: Free, Standalone, PerNode, Per-GB.')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
param logAnalyticsSku string = 'PerNode'

@description('Specifies the workspace data retention in days. -1 means Unlimited retention for the Unlimited Sku. 730 days is the maximum allowed for all other Skus.')
param logAnalyticsRetentionInDays int = 60

@description('Tier of your Azure Container Registry.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Premium'

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

//********************************************
// Variables
//********************************************
var acrName = '${prefix}acr${suffix}'

//********************************************
// Modules and Resources
//********************************************
module workspace 'modules/log-analytics.bicep' = {
  name: 'workspace'
  params: {
    // properties
    name: empty(logAnalyticsName) ? toLower('${prefix}-log-analytics-${suffix}') : logAnalyticsName
    location: location
    tags: tags
    sku: logAnalyticsSku
    retentionInDays: logAnalyticsRetentionInDays
  }
}

module containerRegistry './modules/container-registry.bicep' = {
  name: 'containerRegistry'
  params: {
    name: acrName
    sku: acrSku
    adminUserEnabled: true
    workspaceId: workspace.outputs.id
    location: location
    tags: tags
  }
}

//********************************************
// Outputs
//********************************************
output acrName string = containerRegistry.outputs.name
output acrLoginServer string = containerRegistry.outputs.loginServer
output logAnalyticsWorkspaceName string = workspace.outputs.name
