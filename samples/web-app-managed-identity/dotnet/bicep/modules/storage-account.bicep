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

@description('Specifies the name of the diagnostic settings of the storage account and of its blob service.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories that the diagnostic settings of the blob service send to the Log Analytics workspace (StorageBlobLogs table).')
param blobLogCategories array = [
  'StorageRead'
  'StorageWrite'
  'StorageDelete'
]

@description('Specifies the metric categories that the diagnostic settings of the storage account and of its blob service send to the Log Analytics workspace (AzureMetrics table).')
param metricCategories array = [
  'Transaction'
]

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************
var blobLogs = [
  for category in blobLogCategories: {
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

// The storage account exports only metrics; the logs of the requests to its blobs are exported by its blob service.
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
    logs: blobLogs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************
output id string = storageAccount.id
output name string = storageAccount.name
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
