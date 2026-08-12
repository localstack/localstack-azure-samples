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
param containerName string = 'guestbook'

@description('Specifies the SKU for the container registry.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Basic'

@description('Specifies the name of the container image.')
param imageName string = 'guestbook'

@description('Specifies the tag of the container image.')
param imageTag string = 'v1'

@description('Specifies the CPU cores allocated to the container, as a string so it stays a decimal.')
param containerCpu string = '0.5'

@description('Specifies the memory allocated to the container.')
param containerMemory string = '1Gi'

@description('Specifies the minimum number of replicas.')
@minValue(0)
param minReplicas int = 1

@description('Specifies the maximum number of replicas.')
@minValue(1)
param maxReplicas int = 3

@description('Specifies the revision suffix of the container app template.')
param revisionSuffix string = 'v1'

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

var storageAccountName = '${prefix}acastorage${suffix}'
var acrName = '${prefix}acaacr${suffix}'
var environmentName = '${prefix}-aca-env-${suffix}'
var appName = '${prefix}-aca-guestbook-${suffix}'

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

// Container Apps Managed Environment
resource managedEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {}
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2025-07-01' = {
  name: appName
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: managedEnvironment.id
    configuration: {
      activeRevisionsMode: 'Multiple'
      secrets: [
        {
          name: 'storage-conn'
          value: 'DefaultEndpointsProtocol=http;AccountName=${storageAccountName};AccountKey=${storageAccount.listKeys().keys[0].value};BlobEndpoint=${storageAccount.properties.primaryEndpoints.blob}'
        }
        {
          name: 'registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
      ]
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'registry-password'
        }
      ]
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: true
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      revisionSuffix: revisionSuffix
      containers: [
        {
          name: imageName
          image: '${containerRegistry.properties.loginServer}/${imageName}:${imageTag}'
          resources: {
            cpu: json(containerCpu)
            memory: containerMemory
          }
          env: [
            {
              name: 'AZURE_STORAGE_CONNECTION_STRING'
              secretRef: 'storage-conn'
            }
            {
              name: 'BLOB_CONTAINER_NAME'
              value: containerName
            }
            {
              name: 'APP_REVISION'
              value: revisionSuffix
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scale'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

output storageAccountName string = storageAccount.name
output acrName string = containerRegistry.name
output acrLoginServer string = containerRegistry.properties.loginServer
output environmentName string = managedEnvironment.name
output appName string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
output latestRevisionName string = containerApp.properties.latestRevisionName
