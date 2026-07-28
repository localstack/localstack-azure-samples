//********************************************
// Event Hubs namespace, hubs, consumer groups,
// authorization rules and the schema group
//********************************************

@description('Specifies the name of the Event Hubs namespace.')
param namespaceName string

@description('Specifies the location for all resources.')
param location string

@description('Specifies the Event Hubs namespace SKU. Kafka and Capture require Standard or higher.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param skuName string = 'Standard'

@description('Specifies the number of throughput units for the namespace.')
param capacity int = 1

@description('Enables the Kafka protocol endpoint on the namespace.')
param kafkaEnabled bool = true

@description('Automatically scales throughput units when ingress exceeds the current allocation.')
param isAutoInflateEnabled bool = true

@description('Upper bound for auto-inflate. Must be greater than or equal to capacity.')
param maximumThroughputUnits int = 4

@description('Specifies the name of the event hub carrying payment events.')
param eventHubName string = 'payments'

@description('Specifies the name of the event hub carrying fraud alerts.')
param alertHubName string = 'fraud-alerts'

@description('Number of partitions for the payments hub. Partitions are the unit of parallelism.')
param partitionCount int = 4

@description('Number of partitions for the alerts hub.')
param alertPartitionCount int = 2

@description('Retention for both hubs, in hours.')
param retentionTimeInHours int = 24

@description('Consumer groups created on the payments hub, one per downstream system.')
param consumerGroups array = [
  'fraud-detector'
  'analytics'
  'audit'
]

@description('Resource id of the storage account that receives Capture archives.')
param captureStorageAccountId string

@description('Blob container that receives Capture archives.')
param captureContainerName string

@description('Capture flushes when this many seconds have elapsed, or when the size limit is hit.')
@minValue(60)
@maxValue(900)
param captureIntervalInSeconds int = 60

@description('Capture flushes when this many bytes have accumulated, or when the interval elapses.')
@minValue(10485760)
@maxValue(524288000)
param captureSizeLimitInBytes int = 10485760

@description('Specifies the name of the Schema Registry group.')
param schemaGroupName string = 'payments-schemas'

@description('Specifies the tags for all resources.')
param tags object = {}

resource namespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
    capacity: capacity
  }
  properties: {
    kafkaEnabled: kafkaEnabled
    isAutoInflateEnabled: isAutoInflateEnabled
    maximumThroughputUnits: isAutoInflateEnabled ? maximumThroughputUnits : 0
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// The payments hub archives every event to Blob Storage as Avro. Capture is a property of
// the hub, not a separate pipeline: no consumer has to be written for the cold path.
resource paymentsHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: namespace
  name: eventHubName
  properties: {
    partitionCount: partitionCount
    retentionDescription: {
      cleanupPolicy: 'Delete'
      retentionTimeInHours: retentionTimeInHours
    }
    captureDescription: {
      enabled: true
      encoding: 'Avro'
      intervalInSeconds: captureIntervalInSeconds
      sizeLimitInBytes: captureSizeLimitInBytes
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

resource alertsHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: namespace
  name: alertHubName
  properties: {
    partitionCount: alertPartitionCount
    retentionDescription: {
      cleanupPolicy: 'Delete'
      retentionTimeInHours: retentionTimeInHours
    }
  }
}

// Every downstream system reads the same log through its own consumer group, at its own
// pace, with its own offsets.
resource groups 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = [
  for group in consumerGroups: {
    parent: paymentsHub
    name: group
  }
]

// Least privilege: producers may only Send, consumers may only Listen.
resource sendRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: paymentsHub
  name: 'payments-send'
  properties: {
    rights: [
      'Send'
    ]
  }
}

resource listenRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: paymentsHub
  name: 'payments-listen'
  properties: {
    rights: [
      'Listen'
    ]
  }
}

resource alertSendRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: alertsHub
  name: 'alerts-send'
  properties: {
    rights: [
      'Send'
    ]
  }
}

// The dashboard reads both hubs plus partition runtime metadata, which no single
// entity-level rule covers. That calls for a namespace-wide Listen rule, not the namespace
// Manage key - a reader should never hold Send or Manage.
resource dashboardListenRule 'Microsoft.EventHub/namespaces/authorizationRules@2024-01-01' = {
  parent: namespace
  name: 'dashboard-listen'
  properties: {
    rights: [
      'Listen'
    ]
  }
}

// The contract producers and consumers agree on, versioned by the registry.
resource schemaGroup 'Microsoft.EventHub/namespaces/schemagroups@2024-01-01' = {
  parent: namespace
  name: schemaGroupName
  properties: {
    schemaType: 'Avro'
    schemaCompatibility: 'Forward'
    groupProperties: {}
  }
}

output namespaceName string = namespace.name
output eventHubName string = paymentsHub.name
output alertHubName string = alertsHub.name
output schemaGroupName string = schemaGroup.name

// Connection strings are deliberately NOT exposed as outputs. Secrets in deployment
// outputs are recorded in the deployment history, and deploy.sh reads the keys with
// `az ... authorization-rule keys list` after the template completes, which keeps them out
// of the template altogether.
