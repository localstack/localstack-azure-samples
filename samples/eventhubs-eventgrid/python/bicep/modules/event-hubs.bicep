//********************************************
// Event Hubs namespace and the three hubs the pipeline uses:
//   telemetry            devices publish here; Capture archives it to Blob Storage
//   capture-notifications  Event Grid delivers CaptureFileCreated here
//   curated              the processor writes per-device summaries here
//********************************************

@description('Name of the Event Hubs namespace.')
param namespaceName string

@description('Specifies the location for all resources.')
param location string

@description('Namespace SKU. Capture requires Standard or higher.')
param skuName string = 'Standard'

@description('Hub that receives device telemetry and is archived by Capture.')
param telemetryHubName string = 'telemetry'

@description('Hub that receives the CaptureFileCreated notifications from Event Grid.')
param notificationHubName string = 'capture-notifications'

@description('Hub that receives the curated per-device summaries.')
param curatedHubName string = 'curated'

@description('Partitions on the telemetry hub.')
param telemetryPartitionCount int = 4

@description('Retention for every hub, in hours.')
param retentionTimeInHours int = 24

@description('Resource id of the storage account Capture writes to.')
param captureStorageAccountId string

@description('Blob container that receives Capture archives.')
param captureContainerName string

@description('Capture flush interval, in seconds.')
param captureIntervalInSeconds int = 60

@description('Consumer group the processor reads the notifications hub with.')
param captureConsumerGroup string = 'capture-processor'

@description('Specifies the tags for all resources.')
param tags object = {}

resource namespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
  }
  properties: {
    isAutoInflateEnabled: false
  }
}

resource telemetryHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: namespace
  name: telemetryHubName
  properties: {
    partitionCount: telemetryPartitionCount
    messageRetentionInDays: retentionTimeInHours / 24
    captureDescription: {
      enabled: true
      encoding: 'Avro'
      intervalInSeconds: captureIntervalInSeconds
      sizeLimitInBytes: 10485760
      // Empty windows would otherwise raise a CaptureFileCreated for a file with no readings.
      skipEmptyArchives: true
      destination: {
        name: 'EventHubArchive.AzureBlockBlob'
        properties: {
          storageAccountResourceId: captureStorageAccountId
          blobContainer: captureContainerName
          archiveNameFormat: '{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}'
        }
      }
    }
  }
}

resource notificationHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: namespace
  name: notificationHubName
  properties: {
    partitionCount: 2
    messageRetentionInDays: retentionTimeInHours / 24
  }
}

resource curatedHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: namespace
  name: curatedHubName
  properties: {
    partitionCount: 2
    messageRetentionInDays: retentionTimeInHours / 24
  }
}

// The processor reads the notifications hub through its own consumer group, so its position is
// independent of anything else reading the same stream.
resource processorConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  parent: notificationHub
  name: captureConsumerGroup
}

// Least privilege: producers may only Send to the telemetry hub.
resource telemetrySendRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: telemetryHub
  name: 'telemetry-send'
  properties: {
    rights: [
      'Send'
    ]
  }
}

// The demo scripts read all three hubs, so this one is namespace-wide - but Listen only.
resource pipelineListenRule 'Microsoft.EventHub/namespaces/authorizationRules@2024-01-01' = {
  parent: namespace
  name: 'pipeline-listen'
  properties: {
    rights: [
      'Listen'
    ]
  }
}

output namespaceId string = namespace.id
output namespaceName string = namespace.name
output telemetryHubName string = telemetryHub.name
output notificationHubName string = notificationHub.name
output notificationHubId string = notificationHub.id
output curatedHubName string = curatedHub.name

// Connection strings are deliberately not outputs: anything a template emits is retained in the
// deployment history. deploy.sh reads the keys with the CLI once the resources exist.
