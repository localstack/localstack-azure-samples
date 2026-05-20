//********************************************
// Parameters
//********************************************
@description('Specifies a globally unique name the Azure Web App.')
param name string

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('Specifies the name for the Mongo DB database.')
param databaseName string = 'sampledb'

@minValue(400)
@maxValue(1000000)
@description('Specifies the shared throughput for the Mongo DB database, up to 25 collections.')
param sharedThroughput int = 400

@description('Specifies the name for the Mongo DB collection.')
param collectionName string = 'activities'

@minValue(400)
@maxValue(1000000)
@description('Specifies the dedicated throughput for the Mongo DB collection.')
param dedicatedThroughput int = 400

@description('Specifies a list of field names for which to create single-field indexes on the MongoDB collection.')
param mongoDbIndexKeys array = ['_id','username', 'activity', 'timestamp']

@description('Specifies the primary replica region for the Cosmos DB account.')
param primaryRegion string = 'westeurope'

@description('Specifies the secondary replica region for the Cosmos DB account.')
param secondaryRegion string = 'northeurope'

@allowed([
  'Eventual'
  'ConsistentPrefix'
  'Session'
  'BoundedStaleness'
  'Strong'
])
@description('Specifies the default consistency level of the Cosmos DB account.')
param defaultConsistencyLevel string = 'Eventual'

@allowed([
  '3.2'
  '3.6'
  '4.0'
  '4.2'
  '5.0'
  '6.0'
  '7.0'
  '8.0'
])

@description('Specifies the Cosmos DB server version to use.')
param serverVersion string = '7.0'

@minValue(10)
@maxValue(2147483647)
@description('Specifies the max stale requests. Required for BoundedStaleness. Valid ranges, Single Region: 10 to 2147483647. Multi Region: 100000 to 2147483647.')
param maxStalenessPrefix int = 100000

@minValue(5)
@maxValue(86400)
@description('Specifies the max lag time (seconds). Required for BoundedStaleness. Valid ranges, Single Region: 5 to 84600. Multi Region: 300 to 86400.')
param maxIntervalInSeconds int = 300

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the tags to be applied to the resources.')
param tags object = {}


//********************************************
// Variables
//********************************************
var consistencyPolicy = {
  Eventual: {
    defaultConsistencyLevel: 'Eventual'
  }
  ConsistentPrefix: {
    defaultConsistencyLevel: 'ConsistentPrefix'
  }
  Session: {
    defaultConsistencyLevel: 'Session'
  }
  BoundedStaleness: {
    defaultConsistencyLevel: 'BoundedStaleness'
    maxStalenessPrefix: maxStalenessPrefix
    maxIntervalInSeconds: maxIntervalInSeconds
  }
  Strong: {
    defaultConsistencyLevel: 'Strong'
  }
}
var locations = [
  {
    locationName: primaryRegion
    failoverPriority: 0
    isZoneRedundant: false
  }
  {
    locationName: secondaryRegion
    failoverPriority: 1
    isZoneRedundant: false
  }
]
var diagnosticSettingsName = 'default'
var logCategories = [
  'DataPlaneRequests'
  'MongoRequests'
]
var metricCategories = [
  'Requests'
]
var logs = [for category in logCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: true
    days: 0
  }
}]
var metrics = [for category in metricCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: true
    days: 0
  }
}]

//********************************************
// Resources
//********************************************
resource account 'Microsoft.DocumentDB/databaseAccounts@2025-04-15' = {
  name: toLower(name)
  location: location
  kind: 'MongoDB'
  tags: tags
  properties: {
    consistencyPolicy: consistencyPolicy[defaultConsistencyLevel]
    locations: locations
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: true
    apiProperties: {
      serverVersion: serverVersion
    }
    capabilities: [
      {
        name: 'DisableRateLimitingResponses'
      }
    ]
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/mongodbDatabases@2025-04-15' = {
  parent: account
  name: databaseName
  tags: tags
  properties: {
    resource: {
      id: databaseName
    }
    options: {
      throughput: sharedThroughput
    }
  }
}

resource collection 'Microsoft.DocumentDB/databaseAccounts/mongodbDatabases/collections@2025-04-15' = {
  parent: database
  name: collectionName
  tags: tags
  properties: {
    resource: {
      id: collectionName
      shardKey: {
        username: 'Hash'
      }
      // Use a for loop to dynamically create the 'indexes' array based on the 'mongoDbIndexKeys' parameter
      indexes: [for key in mongoDbIndexKeys: {
        key: {
          keys: [
            key
          ]
        }
      }]
    }
    options: {
      throughput: dedicatedThroughput
    }
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: account
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************
output id string = account.id
output name string = account.name
output documentEndpoint string = account.properties.documentEndpoint
output databaseId string = database.id
output databaseName string = database.name
output collectionId string = collection.id
output collectionName string = collection.name
