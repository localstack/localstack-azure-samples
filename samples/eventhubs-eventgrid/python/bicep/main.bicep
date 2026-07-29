//********************************************
// Cold-path automation on Azure Event Hubs
//
// Capture writes Avro archives to Blob Storage; Event Hubs raises
// Microsoft.EventHub.CaptureFileCreated to an Event Grid system topic; a subscription with an
// EventHub destination turns that notification into a stream; a Function App consumes the stream,
// decodes each archive and writes per-device summaries to a curated hub.
//
// Application code is deployed separately by deploy.sh.
//********************************************

//********************************************
// Parameters
//********************************************
@description('Specifies the prefix for the name of the Azure resources.')
@minLength(2)
param prefix string = 'local'

@description('Specifies the suffix for the name of the Azure resources.')
@minLength(2)
param suffix string = 'telemetry'

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('Event Hubs namespace SKU. Capture requires Standard or higher.')
@allowed([
  'Standard'
  'Premium'
])
param eventHubSkuName string = 'Standard'

@description('Partitions on the telemetry hub.')
@minValue(1)
@maxValue(32)
param telemetryPartitionCount int = 4

@description('Retention for every hub, in hours.')
param retentionTimeInHours int = 24

@description('Capture flush interval, in seconds. 60 is the minimum Azure allows.')
@minValue(60)
@maxValue(900)
param captureIntervalInSeconds int = 60

@description('A reading at or above this is reported as an excursion on the device summary.')
param temperatureLimit int = 80

@description('Specifies the tags for all resources.')
param tags object = {
  sample: 'eventhubs-eventgrid'
  environment: 'localstack'
}

//********************************************
// Variables
//********************************************
var namespaceName = '${prefix}-ehns-${suffix}'
var storageAccountName = toLower('${prefix}ehgrid${take(suffix, 4)}')
var functionAppName = '${prefix}-ehgrid-processor'
var functionPlanName = '${prefix}-ehgrid-plan'
var systemTopicName = '${prefix}-ehns-systopic'
var subscriptionName = 'capture-to-eventhub'
var captureContainerName = 'telemetry-archive'
var telemetryHubName = 'telemetry'
var notificationHubName = 'capture-notifications'
var curatedHubName = 'curated'
var captureConsumerGroup = 'capture-processor'

//********************************************
// Modules
//********************************************
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
    telemetryHubName: telemetryHubName
    notificationHubName: notificationHubName
    curatedHubName: curatedHubName
    telemetryPartitionCount: telemetryPartitionCount
    retentionTimeInHours: retentionTimeInHours
    captureStorageAccountId: storage.outputs.storageAccountId
    captureContainerName: storage.outputs.captureContainerName
    captureIntervalInSeconds: captureIntervalInSeconds
    captureConsumerGroup: captureConsumerGroup
    tags: tags
  }
}

// The Event Grid wiring is its own module because it is the part of this sample worth reading:
// a system topic over the namespace, and a subscription that delivers into an event hub.
module eventGrid 'modules/event-grid.bicep' = {
  name: 'eventgrid-deployment'
  params: {
    systemTopicName: systemTopicName
    subscriptionName: subscriptionName
    location: location
    eventHubNamespaceId: eventHubs.outputs.namespaceId
    notificationHubId: eventHubs.outputs.notificationHubId
    tags: tags
  }
}

module workloads 'modules/workloads.bicep' = {
  name: 'workloads-deployment'
  params: {
    functionAppName: functionAppName
    functionPlanName: functionPlanName
    location: location
    notificationHubName: notificationHubName
    curatedHubName: curatedHubName
    captureConsumerGroup: captureConsumerGroup
    temperatureLimit: temperatureLimit
    tags: tags
  }
}

//********************************************
// Outputs
//********************************************
output resourceGroupName string = resourceGroup().name
output eventHubNamespaceName string = eventHubs.outputs.namespaceName
output telemetryHubName string = eventHubs.outputs.telemetryHubName
output notificationHubName string = eventHubs.outputs.notificationHubName
output curatedHubName string = eventHubs.outputs.curatedHubName
output captureConsumerGroup string = captureConsumerGroup
output storageAccountName string = storage.outputs.storageAccountName
output captureContainerName string = storage.outputs.captureContainerName
output systemTopicName string = eventGrid.outputs.systemTopicName
output eventSubscriptionName string = eventGrid.outputs.eventSubscriptionName
output functionAppName string = workloads.outputs.functionAppName
output temperatureLimit int = temperatureLimit
