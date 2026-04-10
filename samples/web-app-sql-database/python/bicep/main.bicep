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
param appServicePlanZoneRedundant bool = false

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
param repoUrl string = ''

@description('Specifies the tags to be applied to the resources.')
param tags object = {
  environment: 'test'
  iac: 'bicep'
}

@description('Specifies the administrator username of the SQL logical server.')
param administratorLogin string = 'sqladmin'

@description('Specifies the administrator password of the SQL logical server.')
@secure()
param administratorLoginPassword string = 'P@ssw0rd1234!'

@description('Conditional. The Azure Active Directory (AAD) administrator authentication. Required if no `administratorLogin` & `administratorLoginPassword` is provided.')
param administrators object?

@description('Specifies the conditional Developmentresource ID of a user-assigned identityDevelopment to be used by default. This is required if `userAssignedIdentities` is not empty.')
param primaryUserAssignedIdentityResourceId string?

@allowed([
  '1.0'
  '1.1'
  '1.2'
  '1.3'
])
@description('Specifies the optional Developmentminimal TLS versionDevelopment allowed for connections.')
param minimalTlsVersion string = '1.2'

@allowed([
  'Disabled'
  'Enabled'
])
@description('Specifies whether or not to optionally enable IPv6 support for this server.')
param isIPv6Enabled string = 'Disabled'

@description('Specifies the version of the SQL server to deploy.')
param version string = '12.0'

@description('Specifies whether to optionally restrict outbound network access for this server.')
@allowed([
  'Enabled'
  'Disabled'
])
param restrictOutboundNetworkAccess string?

@description('Specifies the name of the SQL Database.')
param sqlDatabaseName string = 'PlannerDB'

@description('Specifies the optional SKU for the database.')
param sku object = {
  name: 'Standard'
  tier: 'Standard'
  capacity: 10
}

@description('Specifies the optional time in minutes after which the database automatically pauses. A value of -1 disables automatic pausing.')
param autoPauseDelay int = -1

@description('Specifies the required Developmentavailability zoneDevelopment. A value of 1, 2, or 3 hardcodes the zone; -1 defines no zone. Note that these are logical availability zones within your Azure subscription. Refer to the Azure documentation for the mapping between physical and logical zones.')
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

@description('Specifies whether or not this database is a Developmentledger databaseDevelopment. All tables will be ledger tables. Note: this value cannot be changed after database creation.')
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

@description('Specifies whether or not this database is Developmentzone redundantDevelopment.')
param sqlDatabaseZoneRedundant bool = false

@description('Specifies the username for the SQL Database.')
param sqlDatabaseUsername string = 'testuser'

@description('Specifies the password for the SQL Database.')
@secure()
param sqlDatabasePassword string = 'TestP@ssw0rd123'

@description('Specifies the required name of the Server Firewall Rule.')
param sqlFirewallRuleName string = 'AllowAllIPs'

@description('Specifies the optional end IP address of the firewall rule. Must be in IPv4 format and greater than or equal to `startIpAddress`. Use \'0.0.0.0\' to allow all Azure-internal IP addresses.')
param endIpAddress string = '255.255.255.255'

@description('Specifies the optional start IP address of the firewall rule. Must be in IPv4 format. Use \'0.0.0.0\' to allow all Azure-internal IP addresses.')
param startIpAddress string = '0.0.0.0'

@description('Specifies the username for the application.')
param username string = 'paolo'

var sqlServerName = '${prefix}-sqlserver-${suffix}'
var webAppName = '${prefix}-webapp-${suffix}'
var appServicePlanName = '${prefix}-app-service-plan-${suffix}'
var keyVaultName = '${prefix}-kv-${suffix}'
var certificateName = '${prefix}-cert-${suffix}'
var sqlConnectionStringSecretName = 'sql-connection-string'
var identity = {
    type: 'SystemAssigned'
  }

resource sqlServer 'Microsoft.Sql/servers@2024-05-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  identity: identity
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    administrators: union({ administratorType: 'ActiveDirectory' }, administrators ?? {})
    federatedClientId: federatedClientId
    isIPv6Enabled: isIPv6Enabled
    version: version
    minimalTlsVersion: minimalTlsVersion
    primaryUserAssignedIdentityId: primaryUserAssignedIdentityResourceId
    publicNetworkAccess: publicNetworkAccess
    restrictOutboundNetworkAccess: restrictOutboundNetworkAccess
  }
}

resource firewallRule 'Microsoft.Sql/servers/firewallRules@2024-11-01-preview' = {
  name: sqlFirewallRuleName
  parent: sqlServer
  properties: {
    endIpAddress: endIpAddress
    startIpAddress: startIpAddress
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2024-11-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
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
    zoneRedundant: sqlDatabaseZoneRedundant
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  kind: appServicePlanKind
  sku: {
    tier: skuTier
    name: skuName
  }
  properties: {
    reserved: reserved
    zoneRedundant: appServicePlanZoneRedundant
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

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: webApp.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
    enableRbacAuthorization: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

resource sqlConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: sqlConnectionStringSecretName
  properties: {
    value: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlDatabaseName};User ID=${sqlDatabaseUsername};Password=${sqlDatabasePassword};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;'
  }
}

resource configAppSettings 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: webApp
  name: 'appsettings'
  properties: {
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    ENABLE_ORYX_BUILD: 'true'
    //Pass Key Vault name and secret name as app settings.
    //The Python SDK will retrieve the actual connection string value from Key Vault
    KEY_VAULT_NAME: keyVaultName
    SECRET_NAME: sqlConnectionStringSecretName
    LOGIN_NAME: username
    KEYVAULT_URI: keyVault.properties.vaultUri
  }
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

output appServicePlanName string = appServicePlan.name
output webAppName string = webApp.name
output webAppUrl string = webApp.properties.defaultHostName
output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
output keyVaultName string = keyVault.name
output keyVaultUrl string = keyVault.properties.vaultUri
output sqlConnectionStringSecretUri string = sqlConnectionStringSecret.properties.secretUri
