//********************************************
// Storage account holding Capture archives, function content and checkpoints
//********************************************

@description('Specifies the name of the storage account.')
param storageAccountName string

@description('Specifies the location for all resources.')
param location string

@description('Blob container that receives Capture archives.')
param captureContainerName string

@description('Specifies the tags for all resources.')
param tags object = {}

@description('Specifies the resource id of the Log Analytics workspace the diagnostic settings send to.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories that the diagnostic settings of the blob, queue and table services send to the workspace (StorageBlobLogs, StorageQueueLogs, StorageTableLogs).')
param serviceLogCategories array = [
  'StorageRead'
  'StorageWrite'
  'StorageDelete'
]

@description('Specifies the metric categories that the diagnostic settings of the account and of its services send to the workspace (AzureMetrics).')
param metricCategories array = [
  'Capacity'
  'Transaction'
]

var serviceLogs = [for category in serviceLogCategories: {
  category: category
  enabled: true
}]
var metrics = [for category in metricCategories: {
  category: category
  enabled: true
}]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource captureContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: captureContainerName
}

// The Functions host keeps its locks, checkpoints and keys in the queues, tables and blobs of the account
resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

// The account offers metrics only; its services send the logs of their requests and their metrics
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: storageAccount
  properties: {
    workspaceId: workspaceId
    metrics: metrics
  }
}

resource blobServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: blobService
  properties: {
    workspaceId: workspaceId
    logs: serviceLogs
    metrics: metrics
  }
}

resource queueServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: queueService
  properties: {
    workspaceId: workspaceId
    logs: serviceLogs
    metrics: metrics
  }
}

resource tableServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: tableService
  properties: {
    workspaceId: workspaceId
    logs: serviceLogs
    metrics: metrics
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output captureContainerName string = captureContainer.name
