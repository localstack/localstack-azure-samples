@description('Specifies the prefix for the name of the Azure resources.')
@minLength(2)
param prefix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the suffix for the name of the Azure resources.')
@minLength(2)
param suffix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('Specifies the sku of the Azure Storage account.')
param storageAccountSku string = 'Standard_LRS'

@description('Specifies the name of the blob container.')
param containerName string = 'activities'

@description('Specifies the SKU for the container registry.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Basic'

@description('Specifies the name of the container image.')
param imageName string = 'vacation-planner'

@description('Specifies the tag of the container image.')
param imageTag string = 'v1'

@description('Specifies the number of CPU cores for the container.')
param cpuCores int = 1

@description('Specifies the memory in GB for the container.')
param memoryInGb int = 1

@description('Specifies the DNS name label for the container group.')
param dnsNameLabel string = '${prefix}-aci-planner-${suffix}'

@description('Specifies the login name passed to the app.')
param loginName string = 'paolo'

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

var storageAccountName = '${prefix}acistorage${suffix}'
var keyVaultName = '${prefix}acikv${suffix}'
var acrName = '${prefix}aciacr${suffix}'
var aciGroupName = '${prefix}-aci-planner-${suffix}'

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  parent: blobServices
  name: containerName
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    accessPolicies: []
  }
}

// Store the storage connection string in Key Vault
resource storageConnSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-conn'
  properties: {
    value: 'DefaultEndpointsProtocol=http;AccountName=${storageAccountName};AccountKey=${storageAccount.listKeys().keys[0].value};BlobEndpoint=${storageAccount.properties.primaryEndpoints.blob}'
  }
}

// Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: true
  }
}

// Container Instance
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: aciGroupName
  location: location
  tags: tags
  properties: {
    containers: [
      {
        name: aciGroupName
        properties: {
          image: '${containerRegistry.properties.loginServer}/${imageName}:${imageTag}'
          resources: {
            requests: {
              cpu: cpuCores
              memoryInGB: memoryInGb
            }
          }
          ports: [
            {
              port: 80
              protocol: 'TCP'
            }
          ]
          environmentVariables: [
            {
              name: 'AZURE_STORAGE_CONNECTION_STRING'
              secureValue: storageConnSecret.properties.secretUri
            }
            {
              name: 'BLOB_CONTAINER_NAME'
              value: containerName
            }
            {
              name: 'LOGIN_NAME'
              value: loginName
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'Always'
    ipAddress: {
      type: 'Public'
      dnsNameLabel: dnsNameLabel
      ports: [
        {
          port: 80
          protocol: 'TCP'
        }
      ]
    }
    imageRegistryCredentials: [
      {
        server: containerRegistry.properties.loginServer
        username: containerRegistry.listCredentials().username
        password: containerRegistry.listCredentials().passwords[0].value
      }
    ]
  }
}

output storageAccountName string = storageAccount.name
output keyVaultName string = keyVault.name
output acrName string = containerRegistry.name
output acrLoginServer string = containerRegistry.properties.loginServer
output aciGroupName string = containerGroup.name
output fqdn string = containerGroup.properties.ipAddress.fqdn
