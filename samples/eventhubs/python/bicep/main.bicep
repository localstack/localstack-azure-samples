//********************************************
// Real-time payment fraud detection on Azure Event Hubs
//
// Deploys the full pipeline: Event Hubs (with Capture, Kafka and a schema group),
// Storage, Key Vault, monitoring, an Event Hubs-triggered Function App and the
// dashboard Web App. Application code is deployed separately by deploy.sh.
//********************************************

//********************************************
// Parameters
//********************************************
@description('Specifies the prefix for the name of the Azure resources.')
@minLength(2)
param prefix string = 'local'

@description('Specifies the suffix for the name of the Azure resources.')
@minLength(2)
param suffix string = 'payments'

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('Specifies the Event Hubs namespace SKU. Capture and Kafka need Standard or higher.')
@allowed([
  'Standard'
  'Premium'
])
param eventHubSkuName string = 'Standard'

@description('Number of partitions for the payments hub.')
@minValue(1)
@maxValue(32)
param partitionCount int = 4

@description('Retention for both hubs, in hours.')
param retentionTimeInHours int = 24

@description('Capture flush interval, in seconds.')
@minValue(60)
@maxValue(900)
param captureIntervalInSeconds int = 60

@description('A single payment at or above this amount is flagged as suspicious.')
param fraudAmountThreshold int = 5000

@description('More than this many payments for one account inside the window is flagged.')
param fraudVelocityCount int = 5

@description('Specifies the tags for all resources.')
param tags object = {
  sample: 'eventhubs-fraud-detection'
  environment: 'localstack'
}

//********************************************
// Variables
//********************************************
var namespaceName = '${prefix}-ehns-${suffix}'
var storageAccountName = toLower('${prefix}ehstorage${take(suffix, 4)}')
var keyVaultName = toLower('${prefix}ehkv${take(suffix, 4)}')
var workspaceName = '${prefix}-eh-logs'
var applicationInsightsName = '${prefix}-eh-insights'
var functionAppName = '${prefix}-eh-fraud-func'
var webAppName = '${prefix}-eh-dashboard'
var functionPlanName = '${prefix}-eh-func-plan'
var webPlanName = '${prefix}-eh-plan'
var captureContainerName = 'payments-archive'
var eventHubName = 'payments'
var alertHubName = 'fraud-alerts'
var fraudConsumerGroup = 'fraud-detector'
var schemaGroupName = 'payments-schemas'

//********************************************
// Modules
//********************************************
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-deployment'
  params: {
    workspaceName: workspaceName
    applicationInsightsName: applicationInsightsName
    location: location
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    storageAccountName: storageAccountName
    location: location
    captureContainerName: captureContainerName
    tags: tags
  }
}

module eventHubs 'modules/event-hubs.bicep' = {
  name: 'eventhubs-deployment'
  params: {
    namespaceName: namespaceName
    location: location
    skuName: eventHubSkuName
    eventHubName: eventHubName
    alertHubName: alertHubName
    partitionCount: partitionCount
    retentionTimeInHours: retentionTimeInHours
    consumerGroups: [
      fraudConsumerGroup
      'analytics'
      'audit'
    ]
    captureStorageAccountId: storage.outputs.storageAccountId
    captureContainerName: storage.outputs.captureContainerName
    captureIntervalInSeconds: captureIntervalInSeconds
    schemaGroupName: schemaGroupName
    tags: tags
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'keyvault-deployment'
  params: {
    keyVaultName: keyVaultName
    location: location
    tags: tags
  }
}

module workloads 'modules/workloads.bicep' = {
  name: 'workloads-deployment'
  params: {
    functionAppName: functionAppName
    webAppName: webAppName
    functionPlanName: functionPlanName
    webPlanName: webPlanName
    location: location
    storageAccountName: storage.outputs.storageAccountName
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    eventHubName: eventHubName
    alertHubName: alertHubName
    fraudConsumerGroup: fraudConsumerGroup
    captureContainerName: captureContainerName
    schemaGroupName: schemaGroupName
    fraudAmountThreshold: fraudAmountThreshold
    fraudVelocityCount: fraudVelocityCount
    tags: tags
  }
}

//********************************************
// Outputs
//********************************************
output resourceGroupName string = resourceGroup().name
output eventHubNamespaceName string = eventHubs.outputs.namespaceName
output eventHubName string = eventHubs.outputs.eventHubName
output alertHubName string = eventHubs.outputs.alertHubName
output schemaGroupName string = eventHubs.outputs.schemaGroupName
output storageAccountName string = storage.outputs.storageAccountName
output captureContainerName string = storage.outputs.captureContainerName
output keyVaultName string = keyVault.outputs.keyVaultName
output functionAppName string = workloads.outputs.functionAppName
output webAppName string = workloads.outputs.webAppName
output dashboardUrl string = workloads.outputs.webAppUrl
