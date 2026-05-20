// Parameters
@description('Specifies the name of the Service Bus namespace.')
param name string

@description('Enabling this property creates a Premium Service Bus Namespace in regions supported availability zones.')
param zoneRedundant bool = true

@description('Specifies the name of Service Bus namespace SKU.')
@allowed([
  'Basic'
  'Premium'
  'Standard'
])
param skuName string = 'Premium'

@description('Specifies the messaging units for the Service Bus namespace. For Premium tier, capacity are 1,2 and 4.')
param capacity int = 1

@description('Specifies a list of queue names.')
param queueNames array = []

@description('Specifies the lock duration of the queue.')
param queueLockDuration string = 'PT5M'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the resource tags.')
param tags object

// Variables
var diagnosticSettingsName = 'diagnosticSettings'
var logCategories = [
  'OperationalLogs'
  'VNetAndIPFilteringLogs'
  'RuntimeAuditLogs'
  'ApplicationMetricsLogs'
]
var metricCategories = [
  'AllMetrics'
]
var logs = [for category in logCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: true
    days: 0
  }
}]
var metrics = [for category in metricCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: true
    days: 0
  }
}]

// Resources
resource namespace 'Microsoft.ServiceBus/namespaces@2025-05-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: capacity
  }
  properties: {
    zoneRedundant: zoneRedundant
  }
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2025-05-01-preview' = [for queueName in queueNames: {
  parent: namespace
  name: queueName
  properties: {
    lockDuration: queueLockDuration
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'P10675199DT2H48M5.4775807S'
    deadLetteringOnMessageExpiration: false
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    maxDeliveryCount: 10
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: false
    enableExpress: false
  }
}]

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: namespace
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

// Outputs
output id string = namespace.id
output name string = namespace.name
output queueIds array = [for i in range(0, length(queueNames)): queue[i].id]
output queueNames array = [for i in range(0, length(queueNames)): queue[i].name]
