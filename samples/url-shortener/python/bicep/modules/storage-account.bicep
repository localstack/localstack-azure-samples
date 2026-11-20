//********************************************
// Parameters
//********************************************

@description('Specifies the name of the storage account.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the SKU of the storage account.')
param skuName string = 'Standard_LRS'

@description('Specifies whether the account allows anonymous access to the containers that ask for it: the QR images container does.')
param allowBlobPublicAccess bool = true

@description('Specifies the name of the table that stores the links.')
param linksTableName string

@description('Specifies the name of the queue of the QR render jobs.')
param qrJobsQueueName string

@description('Specifies the name of the container of the QR images, which anyone can read.')
param qrContainerName string

@description('Specifies the principal id that gets the Storage Table, Queue and Blob Data Contributor roles on the account; none when empty.')
param dataPrincipalId string = ''

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories that the diagnostic settings of the blob, queue and table services send to the Log Analytics workspace (StorageBlobLogs, StorageQueueLogs, StorageTableLogs).')
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
// The built-in roles of the identity that reads and writes the links, the QR jobs and the QR images
var dataRoleDefinitionIds = [
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor
  '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
]

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
    // The qrcodes container uses publicAccess 'Blob'; new storage accounts disallow anonymous access unless the
    // account explicitly allows it.
    allowBlobPublicAccess: allowBlobPublicAccess
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource linksTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2025-01-01' = {
  parent: tableService
  name: linksTableName
}

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource qrJobsQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2025-01-01' = {
  parent: queueService
  name: qrJobsQueueName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource qrContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  parent: blobService
  name: qrContainerName
  properties: {
    publicAccess: 'Blob'
  }
}

resource dataRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleDefinitionId in dataRoleDefinitionIds: if (!empty(dataPrincipalId)) {
  name: guid(storageAccount.id, dataPrincipalId, roleDefinitionId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: dataPrincipalId
    principalType: 'ServicePrincipal'
  }
}]

// The storage account offers metrics only; its services send the logs of their requests and their metrics
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: storageAccount
  properties: {
    workspaceId: workspaceId
    metrics: metrics
  }
}

resource blobServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: blobService
  properties: {
    workspaceId: workspaceId
    logs: serviceLogs
    metrics: metrics
  }
}

resource queueServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: queueService
  properties: {
    workspaceId: workspaceId
    logs: serviceLogs
    metrics: metrics
  }
}

resource tableServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
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
