//********************************************
// Parameters
//********************************************
@description('Specifies the name of the Azure Database for PostgreSQL flexible server.')
param name string

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('Specifies the administrator login for the PostgreSQL server.')
param administratorLogin string = 'pgadmin'

@description('Specifies the administrator login password for the PostgreSQL server.')
@secure()
param administratorLoginPassword string

@description('Specifies the PostgreSQL major version.')
@allowed([
  '13'
  '14'
  '15'
  '16'
  '17'
])
param version string = '16'

@description('Specifies the compute tier of the server.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param skuTier string = 'Burstable'

@description('Specifies the compute SKU name of the server.')
param skuName string = 'Standard_B1ms'

@description('Specifies the storage size in GB.')
@minValue(32)
@maxValue(16384)
param storageSizeGB int = 32

@description('Specifies the backup retention period in days.')
@minValue(7)
@maxValue(35)
param backupRetentionDays int = 7

@description('Specifies whether geo-redundant backup is enabled.')
@allowed([
  'Enabled'
  'Disabled'
])
param geoRedundantBackup string = 'Disabled'

@description('Specifies the high availability mode of the server.')
@allowed([
  'Disabled'
  'SameZone'
  'ZoneRedundant'
])
param highAvailabilityMode string = 'Disabled'

@description('Specifies the create mode of the server.')
@allowed([
  'Default'
  'Create'
  'Update'
])
param createMode string = 'Default'

@description('Specifies whether the server accepts connections from public networks. The deploy machine reaches the server through the firewall rule for the psql bootstrap; the web app reaches it through its private endpoint.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Specifies the name of the database to create on the server.')
param databaseName string = 'PlannerDB'

@description('Specifies the database charset.')
param databaseCharset string = 'UTF8'

@description('Specifies the database collation.')
param databaseCollation string = 'en_US.utf8'

@description('Name of the server-level firewall rule that allows the deploy machine and Azure services to reach the server. Defaults to a permissive allow-all rule appropriate for the sample.')
param firewallRuleName string = 'AllowAllIPs'

@description('Start IP of the firewall rule.')
param firewallStartIp string = '0.0.0.0'

@description('End IP of the firewall rule.')
param firewallEndIp string = '255.255.255.255'

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories enabled by the diagnostic settings.')
param logCategories array = [
  'PostgreSQLLogs'
]

@description('Specifies the metric categories enabled by the diagnostic settings.')
param metricCategories array = [
  'AllMetrics'
]

@description('Specifies whether the retention policy of the diagnostic settings is enabled.')
param retentionPolicyEnabled bool = true

@description('Specifies the retention of the diagnostic settings in days (0 keeps the data as long as the workspace does).')
param retentionPolicyDays int = 0

@description('Specifies the tags to be applied to the resources.')
param tags object = {}

//********************************************
// Variables
//********************************************
var logs = [for category in logCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: retentionPolicyEnabled
    days: retentionPolicyDays
  }
}]
var metrics = [for category in metricCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: retentionPolicyEnabled
    days: retentionPolicyDays
  }
}]

//********************************************
// Resources
//********************************************
// Server is created in public-access mode and fronted by a Private Endpoint (see the
// private-endpoint module in main.bicep). The firewall rule lets the deploy machine reach the
// public endpoint just long enough to run the post-deploy psql bootstrap that creates the
// application role and seed data; the Web App itself reaches the server over the private
// endpoint via the linked Private DNS Zone.
resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: toLower(name)
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    version: version
    createMode: createMode
    storage: {
      storageSizeGB: storageSizeGB
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: geoRedundantBackup
    }
    highAvailability: {
      mode: highAvailabilityMode
    }
    network: {
      publicNetworkAccess: publicNetworkAccess
    }
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: server
  name: databaseName
  properties: {
    charset: databaseCharset
    collation: databaseCollation
  }
}

// Azure runs one operation at a time on a flexible server ("ServerIsBusy" otherwise), so the firewall rule
// waits for the database instead of being created in parallel with it.
resource firewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: server
  name: firewallRuleName
  properties: {
    startIpAddress: firewallStartIp
    endIpAddress: firewallEndIp
  }
  dependsOn: [
    database
  ]
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingsName
  scope: server
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************
output id string = server.id
output name string = server.name
output fqdn string = server.properties.fullyQualifiedDomainName
output databaseId string = database.id
output databaseName string = database.name
