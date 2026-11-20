//********************************************
// Parameters
//********************************************
@description('Specifies the name of the SQL logical server.')
param name string

@description('Specifies the location.')
param location string = resourceGroup().location

@description('Specifies the administrator username of the SQL logical server.')
param administratorLogin string

@description('Specifies the administrator password of the SQL logical server.')
@secure()
param administratorLoginPassword string

@description('Conditional. The Azure Active Directory (AAD) administrator authentication. Required if no `administratorLogin` & `administratorLoginPassword` is provided.')
param administrators object?

@allowed([
  '1.0'
  '1.1'
  '1.2'
  '1.3'
])
@description('Specifies the minimal TLS version allowed for connections.')
param minimalTlsVersion string = '1.2'

@allowed([
  'Disabled'
  'Enabled'
])
@description('Specifies whether or not to optionally enable IPv6 support for this server.')
param isIPv6Enabled string = 'Disabled'

@description('Specifies the version of the SQL server to deploy.')
param version string = '12.0'

@description('Specifies whether the public network access is enabled or disabled')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Specifies whether to optionally restrict outbound network access for this server.')
@allowed([
  'Enabled'
  'Disabled'
])
param restrictOutboundNetworkAccess string?

@description('Specifies the resource id of the user-assigned managed identity the server reads its TDE protector key with.')
param managedIdentityId string

@description('Specifies the required name of the Server Firewall Rule.')
param firewallRuleName string = 'AllowAllIPs'

@description('Specifies the optional start IP address of the firewall rule. Must be in IPv4 format. Use \'0.0.0.0\' to allow all Azure-internal IP addresses.')
param startIpAddress string = '0.0.0.0'

@description('Specifies the optional end IP address of the firewall rule. Must be in IPv4 format and greater than or equal to `startIpAddress`. Use \'0.0.0.0\' to allow all Azure-internal IP addresses.')
param endIpAddress string = '255.255.255.255'

@description('Specifies the name of the SQL Database.')
param databaseName string

@description('Specifies the optional SKU for the database.')
param sku object = {
  name: 'Standard'
  tier: 'Standard'
  capacity: 10
}

@description('Specifies the optional time in minutes after which the database automatically pauses. A value of -1 disables automatic pausing.')
param autoPauseDelay int = -1

@description('Specifies the required availability zone. A value of 1, 2, or 3 hardcodes the zone; -1 defines no zone. Note that these are logical availability zones within your Azure subscription. Refer to the Azure documentation for the mapping between physical and logical zones.')
@allowed([
  -1
  1
  2
  3
])
param availabilityZone int = -1

@description('Specifies the optional collation for the metadata catalog.')
param catalogCollation string = 'DATABASE_DEFAULT'

@description('Specifies the optional collation for the database.')
param collation string = 'SQL_Latin1_General_CP1_CI_AS'

@description('Specifies the optional mode used for database creation.')
param createMode
  | 'Default'
  | 'Copy'
  | 'OnlineSecondary'
  | 'PointInTimeRestore'
  | 'Recovery'
  | 'Restore'
  | 'RestoreExternalBackup'
  | 'RestoreExternalBackupSecondary'
  | 'RestoreLongTermRetentionBackup'
  | 'Secondary' = 'Default'

@description('Specifies the optional resource ID of the elastic pool containing this database.')
param elasticPoolResourceId string?

@description('Specifies the optional Client ID for cross-tenant per-database Customer-Managed Key (CMK) scenarios.')
@minLength(36)
@maxLength(36)
param federatedClientId string?

@description('Specifies the optional behavior when monthly free limits are exhausted for a free database.')
param freeLimitExhaustionBehavior 'AutoPause' | 'BillOverUsage'?

@description('Specifies the optional number of read-only secondary replicas associated with the database.')
param highAvailabilityReplicaCount int = 0

@description('Specifies whether or not this database is a ledger database. All tables will be ledger tables. Note: this value cannot be changed after database creation.')
param isLedgerOn bool = false

@description('Specifies the optional license type to apply for this database.')
param licenseType 'BasePrice' | 'LicenseIncluded'?

@description('Specifies the optional resource identifier of the long-term retention backup used for the create operation.')
param longTermRetentionBackupResourceId string?

@description('Specifies the optional Maintenance Configuration ID assigned to the database, which defines the period for maintenance updates.')
param maintenanceConfigurationId string?

@description('Specifies whether optional customer-controlled manual cutover is required during an Update Database operation to the Hyperscale tier.')
param manualCutover bool?

@description('Specifies the optional minimal capacity (vCores) that the database will always have allocated.')
param minCapacity string = '0'

@description('Specifies the optional trigger for a customer-controlled manual cutover during a wait state while a scaling operation is in progress.')
param performCutover bool?

@description('Specifies the optional type of enclave requested for the database, either Default or VBS enclaves.')
param preferredEnclaveType 'Default' | 'VBS'?

@description('Specifies the optional state of read-only routing.')
param readScale 'Enabled' | 'Disabled' = 'Disabled'

@description('Specifies the optional resource identifier of the recoverable database associated with the create operation.')
param recoverableDatabaseResourceId string?

@description('Specifies the optional resource identifier of the recovery point associated with the create operation.')
param recoveryServicesRecoveryPointResourceId string?

@description('Specifies the optional storage account type to be used for storing database backups.')
param requestedBackupStorageRedundancy 'Geo' | 'GeoZone' | 'Local' | 'Zone' = 'Local'

@description('Specifies the optional resource identifier of the restorable dropped database associated with the create operation.')
param restorableDroppedDatabaseResourceId string?

@description('Specifies the optional point in time (ISO8601 format) of the source database to restore when `createMode` is set to `Restore` or `PointInTimeRestore`.')
param restorePointInTime string?

@description('Specifies the optional name of the sample schema to apply when creating this database.')
param sampleName string = ''

@description('Specifies the optional secondary type of the database, if it is a secondary.')
param secondaryType 'Geo' | 'Named' | 'Standby'?

@description('Specifies the optional time the database was deleted when restoring a deleted database.')
param sourceDatabaseDeletionDate string?

@description('Specifies the optional resource identifier of the source database associated with the create operation.')
param sourceDatabaseResourceId string?

@description('Specifies the optional resource identifier of the source associated with the create operation of this database.')
param sourceResourceId string?

@description('Specifies whether or not the database uses free monthly limits. This is allowed for only one database per subscription.')
param useFreeLimit bool?

@description('Specifies whether or not this database is zone redundant.')
param zoneRedundant bool = false

@description('Specifies the resource id of the Log Analytics workspace.')
param workspaceId string

@description('Specifies the name of the diagnostic settings of the database.')
param diagnosticSettingsName string = 'default'

@description('Specifies the log categories of the database enabled by the diagnostic settings. SQLSecurityAuditEvents carries the records of the database\'s auditing policy, which sends to Azure Monitor.')
param logCategories array = [
  'SQLInsights'
  'AutomaticTuning'
  'QueryStoreRuntimeStatistics'
  'QueryStoreWaitStatistics'
  'Errors'
  'DatabaseWaitStatistics'
  'Timeouts'
  'Blocks'
  'Deadlocks'
  'SQLSecurityAuditEvents'
]

@description('Specifies the metric categories of the database enabled by the diagnostic settings: every one a database has. WorkloadManagement groups the metrics of dedicated SQL pools, so a database of this sample exports none of them.')
param metricCategories array = [
  'Basic'
  'InstanceAndAppAdvanced'
  'WorkloadManagement'
]

@description('Specifies the action groups the auditing policy of the database records. The default is Azure\'s: BATCH_COMPLETED_GROUP, SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP and FAILED_DATABASE_AUTHENTICATION_GROUP.')
param auditActionsAndGroups array = [
  'BATCH_COMPLETED_GROUP'
  'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
  'FAILED_DATABASE_AUTHENTICATION_GROUP'
]

@description('Specifies the resource tags.')
param tags object

//********************************************
// Variables
//********************************************
var logs = [
  for category in logCategories: {
    category: category
    enabled: true
  }
]
var metrics = [
  for category in metricCategories: {
    category: category
    enabled: true
  }
]

//********************************************
// Resources
//********************************************
resource sqlServer 'Microsoft.Sql/servers@2024-05-01-preview' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    administrators: union({ administratorType: 'ActiveDirectory' }, administrators ?? {})
    federatedClientId: federatedClientId
    isIPv6Enabled: isIPv6Enabled
    version: version
    minimalTlsVersion: minimalTlsVersion
    primaryUserAssignedIdentityId: managedIdentityId
    publicNetworkAccess: publicNetworkAccess
    restrictOutboundNetworkAccess: restrictOutboundNetworkAccess
  }
}

resource firewallRule 'Microsoft.Sql/servers/firewallRules@2024-11-01-preview' = {
  name: firewallRuleName
  parent: sqlServer
  properties: {
    endIpAddress: endIpAddress
    startIpAddress: startIpAddress
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2024-11-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: sku
  properties: {
    autoPauseDelay: autoPauseDelay
    availabilityZone: availabilityZone != -1 ? string(availabilityZone) : 'NoPreference'
    catalogCollation: catalogCollation
    collation: collation
    createMode: createMode
    elasticPoolId: elasticPoolResourceId
    federatedClientId: federatedClientId
    freeLimitExhaustionBehavior: freeLimitExhaustionBehavior
    highAvailabilityReplicaCount: highAvailabilityReplicaCount
    isLedgerOn: isLedgerOn
    licenseType: licenseType
    longTermRetentionBackupResourceId: longTermRetentionBackupResourceId
    maintenanceConfigurationId: maintenanceConfigurationId
    manualCutover: manualCutover
    minCapacity: !empty(minCapacity) ? json(minCapacity) : 0
    performCutover: performCutover
    preferredEnclaveType: preferredEnclaveType
    readScale: readScale
    recoverableDatabaseId: recoverableDatabaseResourceId
    recoveryServicesRecoveryPointId: recoveryServicesRecoveryPointResourceId
    requestedBackupStorageRedundancy: requestedBackupStorageRedundancy
    restorableDroppedDatabaseId: restorableDroppedDatabaseResourceId
    restorePointInTime: restorePointInTime
    sampleName: sampleName
    secondaryType: secondaryType
    sourceDatabaseDeletionDate: sourceDatabaseDeletionDate
    sourceDatabaseId: sourceDatabaseResourceId
    sourceResourceId: sourceResourceId
    useFreeLimit: useFreeLimit
    zoneRedundant: zoneRedundant
  }
}

// Auditing of the database to Azure Monitor: the database's diagnostic settings below send its records
// (SQLSecurityAuditEvents) to the workspace, one for each batch the app runs and each sign-in.
resource auditingSettings 'Microsoft.Sql/servers/databases/extendedAuditingSettings@2024-11-01-preview' = {
  parent: sqlDatabase
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
    auditActionsAndGroups: auditActionsAndGroups
  }
}

// The database writes its resource logs to the AzureDiagnostics table: none of its categories has a resource-specific
// table.
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: diagnosticSettingsName
  scope: sqlDatabase
  properties: {
    workspaceId: workspaceId
    logs: logs
    metrics: metrics
  }
}

//********************************************
// Outputs
//********************************************
output id string = sqlServer.id
output name string = sqlServer.name
output fullyQualifiedDomainName string = sqlServer.properties.fullyQualifiedDomainName
output databaseId string = sqlDatabase.id
output databaseName string = sqlDatabase.name
