//********************************************
// Parameters
//********************************************

@description('Specifies the name for the Azure Storage Account resource.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies whether to allow public network access for the storage account.')
@allowed([
  'Disabled'
  'Enabled'
])
param publicNetworkAccess string = 'Disabled'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the the storage SKU.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_GZRS'
  'Standard_RAGRS'
  'Standard_RAGZRS'
  'Premium_LRS'
  'Premium_ZRS'
])
param skuName string = 'Standard_LRS'

@description('Specifies the access tier of the storage account. The default value is Hot.')
param accessTier string = 'Hot'

@description('Specifies whether the storage account allows public access to blobs.')
param allowBlobPublicAccess bool = true

@description('Specifies whether the storage account allows shared key access.')
param allowSharedKeyAccess bool = true

@description('Specifies whether the storage account allows cross-tenant replication.')
param allowCrossTenantReplication bool = false

@description('Specifies the minimum TLS version to be permitted on requests to storage. The default value is TLS1_2.')
param minimumTlsVersion string = 'TLS1_2'

@description('The default action of allow or deny when no other rules match. Allowed values: Allow or Deny')
@allowed([
  'Allow'
  'Deny'
])
param networkAclsDefaultAction string = 'Deny'

@description('Specifies whether Hierarchical Namespace is enabled.')
param isHnsEnabled bool = false

@description('Specifies whether NFSv3 is enabled.')
param isNfsV3Enabled bool = false

@description('Specifies the key expiration period in days.')
param keyExpirationPeriodInDays int = 7

@description('Specifies whether the storage account should only support HTTPS traffic.')
param supportsHttpsTrafficOnly bool = true

@description('Specifies whether large file shares are enabled. The default value is Disabled.')
@allowed([
  'Disabled'
  'Enabled'
])
param largeFileSharesState string = 'Disabled'

@description('Specifies the resource tags.')
param tags object

@description('Specifies whether to create containers.')
param createContainers bool = false

@description('Specifies an array of containers to create.')
param containerNames array = []

@description('Specifies whether to create file shares.')
param createFileShares bool = false

@description('Specifies an array of file shares to create.')
param fileShareNames array = []

//********************************************
// Variables
//********************************************

var diagnosticSettingsName = 'diagnosticSettings'
var logCategories = [
  'StorageRead'
  'StorageWrite'
  'StorageDelete'
]
var metricCategories = [
  'Transaction'
]
var logs = [
  for category in logCategories: {
    category: category
    enabled: true
    retentionPolicy: {
      enabled: true
      days: 0
    }
  }
]
var metrics = [
  for category in metricCategories: {
    category: category
    enabled: true
    retentionPolicy: {
      enabled: true
      days: 0
    }
  }
]

//********************************************
// Resources
//********************************************

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'StorageV2'

  // Containers live inside of a blob service
  resource blobService 'blobServices' = {
    name: 'default'

    // Creating containers with provided names if contition is true
    resource containers 'containers' = [
      for containerName in containerNames: if (createContainers) {
        name: containerName
        properties: {
          publicAccess: 'None'
        }
      }
    ]
  }

  resource queueService 'queueServices' = {
    name: 'default'
  }

  resource tableService 'tableServices' = {
    name: 'default'
  }

  resource fileService 'fileServices' = {
    name: 'default'
  
    // Creating file shares with provided names if contition is true
    resource shares 'shares' = [
      for fileShareName in fileShareNames: if (createFileShares) {
        name: fileShareName
        properties: {
          enabledProtocols: 'SMB'
          shareQuota: 100 // Quota in GB (adjust as needed)
        }
      }
    ]
  }

  properties: {
    publicNetworkAccess: publicNetworkAccess
    accessTier: accessTier
    allowBlobPublicAccess: allowBlobPublicAccess
    allowCrossTenantReplication: allowCrossTenantReplication
    allowSharedKeyAccess: allowSharedKeyAccess
    encryption: {
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: false
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
        queue: {
          enabled: true
          keyType: 'Service'
        }
        table: {
          enabled: true
          keyType: 'Service'
        }
      }
    }
    isHnsEnabled: isHnsEnabled
    isNfsV3Enabled: isNfsV3Enabled
    keyPolicy: {
      keyExpirationPeriodInDays: keyExpirationPeriodInDays
    }
    largeFileSharesState: largeFileSharesState
    minimumTlsVersion: minimumTlsVersion
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: networkAclsDefaultAction
    }
    supportsHttpsTrafficOnly: supportsHttpsTrafficOnly
  }
}

resource blobServicesDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${diagnosticSettingsName}-blobService'
  scope: storageAccount::blobService
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

resource queueServicesDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${diagnosticSettingsName}-queueService'
  scope: storageAccount::queueService
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}


resource tableServicesDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${diagnosticSettingsName}-tableService'
  scope: storageAccount::tableService
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

resource fileServicesDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${diagnosticSettingsName}-fileService'
  scope: storageAccount::fileService
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************

output id string = storageAccount.id
output name string = storageAccount.name
output connectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
