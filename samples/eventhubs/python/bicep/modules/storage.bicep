//********************************************
// Storage account for Capture archives, Function App
// checkpoints and Function App content
//********************************************

@description('Specifies the name of the storage account.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Specifies the location for all resources.')
param location string

@description('Specifies the storage account SKU.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
])
param skuName string = 'Standard_LRS'

@description('Blob container that receives Event Hubs Capture archives.')
param captureContainerName string = 'payments-archive'

@description('Specifies the tags for all resources.')
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource captureContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: captureContainerName
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output captureContainerName string = captureContainer.name

// The storage connection string is likewise left to deploy.sh: it must be built from the
// account's own endpoints (see scripts/deploy.sh) and would otherwise land in the
// deployment history.
