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

@description('Specifies the tags to be applied to the resources.')
param tags object = {}

//********************************************
// Variables
//********************************************
var diagnosticSettingsName = 'default'
var logCategories = [
  'PostgreSQLLogs'
]
var metricCategories = [
  'AllMetrics'
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
    createMode: 'Default'
    storage: {
      storageSizeGB: storageSizeGB
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
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

resource firewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: server
  name: firewallRuleName
  properties: {
    startIpAddress: firewallStartIp
    endIpAddress: firewallEndIp
  }
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
