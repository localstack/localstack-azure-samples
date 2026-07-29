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

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output captureContainerName string = captureContainer.name
