//********************************************
// Parameters
//********************************************
@description('Specifies the name of the Log Analytics workspace.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the service tier of the workspace: Free, Standalone, PerNode, Per-GB.')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
param sku string = 'PerNode'

@description('Specifies the workspace data retention in days. -1 means Unlimited retention for the Unlimited Sku. 730 days is the maximum allowed for all other Skus.')
param retentionInDays int = 60

@description('Specifies the name of the diagnostic settings of the workspace.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories that the diagnostic settings of the workspace send to the workspace itself. Audit records the queries run on the workspace in the LAQueryLogs table.')
param logCategories array = [
  'Audit'
]

@description('Specifies the metric categories that the diagnostic settings of the workspace send to the workspace itself.')
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
resource workspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: name
  tags: tags
  location: location
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
  }
}

// Query auditing: the diagnostic settings of a workspace can send its audit records to the workspace itself.
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: workspace
  properties: {
    workspaceId: workspace.id
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************
output id string = workspace.id
output name string = workspace.name
output customerId string = workspace.properties.customerId
