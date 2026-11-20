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
param queueLockDuration string = 'PT1M'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the resource tags.')
param tags object

@description('Specifies the principal id that gets the Azure Service Bus Data Sender and Receiver roles on the namespace; none when empty.')
param dataPrincipalId string = ''

@description('Specifies where the diagnostic settings write the logs in the workspace: Dedicated writes them to the resource-specific AZMS tables that Microsoft recommends, AzureDiagnostics to the shared AzureDiagnostics table.')
@allowed([
  'AzureDiagnostics'
  'Dedicated'
])
param logAnalyticsDestinationType string = 'Dedicated'

// Variables
var diagnosticSettingsName = 'diagnosticSettings'
// The runtime audit logs are left out: Service Bus writes them only in the Premium tier
var logCategories = [
  'OperationalLogs'
  'VNetAndIPFilteringLogs'
  'DiagnosticErrorLogs'
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

// The built-in roles of the identity that sends and receives the link events
var dataRoleDefinitionIds = [
  '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39' // Azure Service Bus Data Sender
  '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0' // Azure Service Bus Data Receiver
]

resource dataRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleDefinitionId in dataRoleDefinitionIds: if (!empty(dataPrincipalId)) {
  name: guid(namespace.id, dataPrincipalId, roleDefinitionId)
  scope: namespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: dataPrincipalId
    principalType: 'ServicePrincipal'
  }
}]

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: namespace
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: logAnalyticsDestinationType
    logs: logs
    metrics: metrics
  }
}

// Outputs
output id string = namespace.id
output name string = namespace.name
output queueIds array = [for i in range(0, length(queueNames)): queue[i].id]
output queueNames array = [for i in range(0, length(queueNames)): queue[i].name]
