//********************************************
// Parameters
//********************************************
@description('Specifies the name of the Azure Database for MySQL flexible server.')
param name string

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('Specifies the administrator login for the MySQL server.')
param administratorLogin string = 'myadmin'

@description('Specifies the administrator login password for the MySQL server.')
@secure()
param administratorLoginPassword string

@description('Specifies the MySQL major version.')
@allowed([
  '5.7'
  '8.0.21'
])
param version string = '8.0.21'

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
@minValue(20)
@maxValue(16384)
param storageSizeGB int = 32

@description('Specifies the backup retention period in days.')
@minValue(1)
@maxValue(35)
param backupRetentionDays int = 7

@description('Specifies the name of the database to create on the server.')
param databaseName string = 'PlannerDB'

@description('Specifies the database charset.')
param databaseCharset string = 'utf8mb4'

@description('Specifies the database collation.')
param databaseCollation string = 'utf8mb4_unicode_ci'

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
  'MySqlSlowLogs'
  'MySqlAuditLogs'
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
// public endpoint just long enough to run the post-deploy mysql bootstrap that creates the
// application user and seed data; the Web App itself reaches the server over the private
// endpoint via the linked Private DNS Zone.
resource server 'Microsoft.DBforMySQL/flexibleServers@2023-12-30' = {
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

resource database 'Microsoft.DBforMySQL/flexibleServers/databases@2023-12-30' = {
  parent: server
  name: databaseName
  properties: {
    charset: databaseCharset
    collation: databaseCollation
  }
}

resource firewallRule 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2023-12-30' = {
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
