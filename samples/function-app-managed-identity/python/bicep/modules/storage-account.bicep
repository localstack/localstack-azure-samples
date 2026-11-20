//********************************************
// Parameters
//********************************************
@description('Specifies the globally unique name of the Azure Storage account.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the sku of the Azure Storage account.')
param skuName string = 'Standard_LRS'

@description('Specifies the access tier of the Azure Storage account.')
@allowed([
  'Hot'
  'Cool'
])
param accessTier string = 'Hot'

@description('Specifies the names of the blob containers to create.')
param containerNames array = []

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings of the storage account and of its services.')
param diagnosticSettingsName string = 'default'

@description('Specifies the services of the storage account whose diagnostic settings send their resource logs and metrics to the Log Analytics workspace: blob (StorageBlobLogs), queue (StorageQueueLogs), table (StorageTableLogs).')
param diagnosticServices array = [
  'blob'
]

@description('Specifies the log categories that the diagnostic settings of the services send to the Log Analytics workspace.')
param serviceLogCategories array = [
  'StorageRead'
  'StorageWrite'
  'StorageDelete'
]

@description('Specifies the metric categories that the diagnostic settings of the storage account and of its services send to the Log Analytics workspace (AzureMetrics table): Capacity holds the hourly capacity metrics, Transaction the metrics of the requests.')
param metricCategories array = [
  'Capacity'
  'Transaction'
]

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************
var serviceLogs = [
  for category in serviceLogCategories: {
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
var hasDiagnostics = !empty(workspaceId)

//********************************************
// Resources
//********************************************
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: accessTier
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = [
  for containerName in containerNames: {
    parent: blobService
    name: containerName
  }
]

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2025-01-01' = if (contains(diagnosticServices, 'queue')) {
  parent: storageAccount
  name: 'default'
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2025-01-01' = if (contains(diagnosticServices, 'table')) {
  parent: storageAccount
  name: 'default'
}

// The storage account exports only metrics; the logs of the requests to its blobs, queues and tables are exported by
// the diagnostic settings of its services.
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (hasDiagnostics) {
  name: diagnosticSettingsName
  scope: storageAccount
  properties: {
    workspaceId: workspaceId
    metrics: metrics
  }
}

resource blobServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (hasDiagnostics && contains(diagnosticServices, 'blob')) {
  name: diagnosticSettingsName
  scope: blobService
  properties: {
    workspaceId: workspaceId
    logs: serviceLogs
    metrics: metrics
  }
}

resource queueServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (hasDiagnostics && contains(diagnosticServices, 'queue')) {
  name: diagnosticSettingsName
  scope: queueService
  properties: {
    workspaceId: workspaceId
    logs: serviceLogs
    metrics: metrics
  }
}

resource tableServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (hasDiagnostics && contains(diagnosticServices, 'table')) {
  name: diagnosticSettingsName
  scope: tableService
  properties: {
    workspaceId: workspaceId
    logs: serviceLogs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************
output id string = storageAccount.id
output name string = storageAccount.name
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output queueEndpoint string = storageAccount.properties.primaryEndpoints.queue
output tableEndpoint string = storageAccount.properties.primaryEndpoints.table
