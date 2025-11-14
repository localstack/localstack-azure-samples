@description('Specifies the prefix for the name of the Azure resources.')
@minLength(2)
param prefix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the suffix for the name of the Azure resources.')
@minLength(2)
param suffix string = take(uniqueString(resourceGroup().id), 4)

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('Specifies the tier name for the hosting plan.')
@allowed([
  'Basic'
  'Standard'
  'ElasticPremium'
  'Premium'
  'PremiumV2'
  'Premium0V3'
  'PremiumV3'
  'PremiumMV3'
  'Isolated'
  'IsolatedV2'
  'WorkflowStandard'
  'FlexConsumption'
])
param skuTier string = 'Standard'

@description('Specifies the SKU name for the hosting plan.')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'EP1'
  'EP2'
  'EP3'
  'P1'
  'P2'
  'P3'
  'P1V2'
  'P2V2'
  'P3V2'
  'P0V3'
  'P1V3'
  'P2V3'
  'P3V3'
  'P1MV3'
  'P2MV3'
  'P3MV3'
  'P4MV3'
  'P5MV3'
  'I1'
  'I2'
  'I3'
  'I1V2'
  'I2V2'
  'I3V2'
  'I4V2'
  'I5V2'
  'I6V2'
  'WS1'
  'WS2'
  'WS3'
  'FC1'
])
param skuName string = 'S1'

@description('Specifies the kind of the hosting plan.')
@allowed([
  'app'
  'elastic'
  'functionapp'
  'windows'
  'linux'
])
param appServicePlanKind string = 'linux'

@description('Specifies whether the hosting plan is reserved.')
param reserved bool = true

@description('Specifies whether the hosting plan is zone redundant.')
param zoneRedundant bool = false

@description('Specifies the language runtime used by the Azure Web App.')
@allowed([
  'dotnet'
  'dotnet-isolated'
  'python'
  'java'
  'node'
  'powerShell'
  'custom'
])
param runtimeName string

@description('Specifies the target language version used by the Azure Web App.')
param runtimeVersion string

@description('Specifies the kind of the hosting plan.')
@allowed([
  'app'                                    // Windows Web app
  'app,linux'                              // Linux Web app
  'app,linux,container'                    // Linux Container Web app
  'hyperV'                                 // Windows Container Web App
  'app,container,windows'                  // Windows Container Web App
  'app,linux,kubernetes'                   // Linux Web App on ARC
  'app,linux,container,kubernetes'         // Linux Container Web App on ARC
  'functionapp'                            // Function Code App
  'functionapp,linux'                      // Linux Consumption Function app
  'functionapp,linux,container,kubernetes' // Function Container App on ARC
  'functionapp,linux,kubernetes'           // Function Code App on ARC
])
param webAppKind string = 'app,linux'

@description('Specifies whether HTTPS is enforced for the Azure Web App.')
param httpsOnly bool = false

@description('Specifies the minimum TLS version for the Azure Web App.')
@allowed([
  '1.0'
  '1.1'
  '1.2'
  '1.3'
])
param minTlsVersion string = '1.2'

@description('Specifies whether the public network access is enabled or disabled')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Specifies the optional Git Repo URL.')
param repoUrl string = ' '

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

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

@description('Specifies the username for the application.')
param username string = 'paolo'

var webAppName = '${prefix}-webapp-${suffix}'
var appServicePlanPortalName = '${prefix}-app-service-plan-${suffix}'
var accountName = '${prefix}-mongodb-${suffix}'
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

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanPortalName
  location: location
  tags: tags
  kind: appServicePlanKind
  sku: {
    tier: skuTier
    name: skuName
  }
  properties: {
    reserved: reserved
    zoneRedundant: zoneRedundant
     maximumElasticWorkerCount: skuTier == 'FlexConsumption' ? 1 : 20
  }
}

resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: webAppName
  location: location
  tags: tags
  kind: webAppKind
  properties: {
    httpsOnly: httpsOnly
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: toUpper('${runtimeName}|${runtimeVersion}')
      minTlsVersion: minTlsVersion
      publicNetworkAccess: publicNetworkAccess
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource configAppSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: webApp
  name: 'appsettings'
  properties: {
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    ENABLE_ORYX_BUILD: 'true'
    COSMOSDB_CONNECTION_STRING: account.listConnectionStrings().connectionStrings[0].connectionString
    COSMOSDB_DATABASE_NAME: databaseName
    COSMOSDB_COLLECTION_NAME: collectionName
    LOGIN_NAME: username
  }
  dependsOn: [
    collection
  ]
}

resource webAppSourceControl 'Microsoft.Web/sites/sourcecontrols@2024-11-01' = if (contains(repoUrl,'http')){
  name: 'web'
  parent: webApp
  properties: {
    repoUrl: repoUrl
    branch: 'master'
    isManualIntegration: true
  }
}

resource account 'Microsoft.DocumentDB/databaseAccounts@2025-04-15' = {
  name: toLower(accountName)
  location: location
  kind: 'MongoDB'
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

output webAppName string = webAppName
output accountName string = accountName
output databaseName string = databaseName
output collectionName string = collectionName
output documentEndpoint string = account.properties.documentEndpoint
