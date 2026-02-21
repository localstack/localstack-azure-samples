// PostgreSQL Flexible Server sample — Bicep template
//
// Deploys a PostgreSQL Flexible Server with a database and firewall rule.
//
// NOTE: Bicep deployments use the LocalStack ARM template parser, which is an
// x86-64 binary. On ARM64 machines (e.g. Apple Silicon), this requires Rosetta
// or an x86-64 Docker environment.

// Parameters
@description('Specifies the name prefix for PostgreSQL Flexible Server resources.')
@minLength(3)
@maxLength(10)
param serverNamePrefix string = 'pgflex'

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('Specifies the administrator login name.')
param administratorLogin string = 'pgadmin'

@description('Specifies the administrator login password.')
@secure()
param administratorLoginPassword string

@description('Specifies the PostgreSQL version.')
@allowed([
  '13'
  '14'
  '15'
  '16'
])
param version string = '16'

@description('Specifies the SKU name for the server.')
param skuName string = 'B_Standard_B1ms'

@description('Specifies the SKU tier for the server.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param skuTier string = 'Burstable'

@description('Specifies the storage size in GB.')
param storageSizeGB int = 32

@description('Specifies the name of the database to create.')
param databaseName string = 'sampledb'

@description('Specifies the firewall rule name.')
param firewallRuleName string = 'allow-all'

@description('Specifies the start IP address for the firewall rule.')
param firewallStartIp string = '0.0.0.0'

@description('Specifies the end IP address for the firewall rule.')
param firewallEndIp string = '255.255.255.255'

// Variables
var serverName = '${serverNamePrefix}-${uniqueString(resourceGroup().id)}'

// Resources
resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    version: version
    storage: {
      storageSizeGB: storageSizeGB
    }
    highAvailability: {
      mode: 'Disabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  name: databaseName
  parent: server
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource firewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  name: firewallRuleName
  parent: server
  properties: {
    startIpAddress: firewallStartIp
    endIpAddress: firewallEndIp
  }
}

// Outputs
output serverName string = server.name
output serverFqdn string = server.properties.fullyQualifiedDomainName
output databaseName string = database.name
output firewallRuleName string = firewallRule.name
output serverId string = server.id
