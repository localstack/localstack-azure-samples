//********************************************
// Parameters
//********************************************
@description('Specifies the name of the App Service Plan.')
param name string

@description('Specifies the location.')
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
param kind string = 'linux'

@description('Specifies whether the hosting plan is reserved.')
param reserved bool = true

@description('Specifies whether the hosting plan is zone redundant.')
param zoneRedundant bool = false

@description('Specifies the maximum number of elastic workers of the hosting plan.')
param maximumElasticWorkerCount int = 20

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories enabled by the diagnostic settings.')
param logCategories array = []

@description('Specifies the metric categories enabled by the diagnostic settings.')
param metricCategories array = [
  'AllMetrics'
]

@description('Specifies whether the retention policy of the diagnostic settings is enabled.')
param retentionPolicyEnabled bool = true

@description('Specifies the retention of the diagnostic settings in days (0 keeps the data as long as the workspace does).')
param retentionPolicyDays int = 0

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the tags to be applied to the resources.')
param tags object = {}

//********************************************
// Variables
//********************************************

var logs = [
  for category in logCategories: {
    category: category
    enabled: true
    retentionPolicy: {
      enabled: retentionPolicyEnabled
      days: retentionPolicyDays
    }
  }
]
var metrics = [
  for category in metricCategories: {
    category: category
    enabled: true
    retentionPolicy: {
      enabled: retentionPolicyEnabled
      days: retentionPolicyDays
    }
  }
]

//********************************************
// Resources
//********************************************
resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: name
  location: location
  tags: tags
  kind: kind
  sku: {
    tier: skuTier
    name: skuName
  }
  properties: {
    reserved: reserved
    zoneRedundant: zoneRedundant
    maximumElasticWorkerCount: maximumElasticWorkerCount
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if(!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: appServicePlan
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************
output id string = appServicePlan.id
output name string = appServicePlan.name
