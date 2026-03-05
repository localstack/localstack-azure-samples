//********************************************
// Parameters
//********************************************
@description('Specifies the prefix for the name of the Azure resources.')
@minLength(2)
param prefix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the suffix for the name of the Azure resources.')
@minLength(2)
param suffix string = take(uniqueString(resourceGroup().id), 4)

@description('Enabling this property creates a Premium Service Bus Namespace in regions supported availability zones.')
param zoneRedundant bool = true

@description('Specifies the name of Service Bus namespace SKU.')
@allowed([
  'Basic'
  'Premium'
  'Standard'
])
param skuName string = 'Standard'

@description('Specifies the messaging units for the Service Bus namespace. For Premium tier, capacity are 1,2 and 4.')
param capacity int = 1

@description('Specifies the name of the Service Bus queue.')
param queueName string

@description('Specifies the lock duration of the queue.')
param lockDuration string = 'PT5M'

@description('Specifies the maximum number of deliveries for a message.')
param maxDeliveryCount int = 10

@description('ISO 8601 timeSpan idle interval after which the topic is automatically deleted. The minimum duration is 5 minutes.')
param autoDeleteOnIdle string = 'P10675199DT2H48M5.4775807S' // Default to max value as per Azure docs

@description('ISO 8601 default message time to live value. This is the duration after which the message expires, starting from when the message is sent to Service Bus. This is the default value used unless DefaultMessageTimeToLive is explicitly set on a message.')
param defaultMessageTimeToLive string = 'P10675199DT2H48M5.4775807S' // Default to max value

@description('ISO 8601 duration of the duplicate detection history. The default value is 10 minutes.')
param duplicateDetectionHistoryTimeWindow string = 'PT10M'

@description('Value that indicates whether operations for the topic are batched.')
param enableBatchedOperations bool = true

@description('A value that indicates whether the topic has dead-lettering on message expiration. If true, messages that expire will be moved to the dead-letter sub-queue.')
param deadLetteringOnMessageExpiration bool = false

@description('The maximum size of the topic in megabytes, which is the size of memory allocated for the topic. Default is 1024 MB (1 GB).')
param maxSizeInMegabytes int = 1024

@description('A value indicating if this topic requires duplicate detection. If value is true, then DuplicateDetectionHistoryTimeWindow will be required.')
param requiresDuplicateDetection bool = false

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the resource tags.')
param tags object = {}

//********************************************
// Variables
//********************************************
var namespaceName = '${prefix}-sb-ns-${suffix}'

//********************************************
// Resources
//********************************************
resource namespace 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: capacity
  }
  properties: {
    zoneRedundant: zoneRedundant
  }
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: namespace
  name: queueName
  properties: {
    enableBatchedOperations: enableBatchedOperations
    requiresDuplicateDetection: requiresDuplicateDetection
    requiresSession: false
    defaultMessageTimeToLive: defaultMessageTimeToLive
    deadLetteringOnMessageExpiration: deadLetteringOnMessageExpiration
    duplicateDetectionHistoryTimeWindow: duplicateDetectionHistoryTimeWindow
    maxDeliveryCount: maxDeliveryCount
    lockDuration: lockDuration
    maxSizeInMegabytes: maxSizeInMegabytes
    autoDeleteOnIdle: autoDeleteOnIdle
    enablePartitioning: false
    enableExpress: false
  }
}

//********************************************
// Outputs
//********************************************
output namespaceId string = namespace.id
output name string = namespace.name
output queueId string = queue.id
output queueName string = queue.name
